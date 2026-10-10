//
//  FirebaseIntegrationTests.swift
//  CampusSyncTests
//
//  Runs the REAL FirebaseAuthBackend against the LOCAL Firebase emulators, so the
//  Swift code and firestore.rules are tested together. Skipped unless
//  FIREBASE_EMULATOR_HOST is set, and refuses to run if the app is not actually
//  pointed at the emulator, so it can never write to the real project.
//
//  Run with: firebase/run-app-tests.sh
//

import FirebaseFirestore
import Foundation
import Testing
@testable import CampusSync

private let emulatorHost = ProcessInfo.processInfo.environment["FIREBASE_EMULATOR_HOST"]

@MainActor
@Suite(.enabled(if: emulatorHost != nil), .serialized)
struct FirebaseIntegrationTests {
    private let backend = FirebaseAuthBackend()

    private func requireEmulator() throws {
        // Hard stop: if this is not the emulator, never continue.
        let host = try #require(emulatorHost)
        #expect(Firestore.firestore().settings.host == "\(host):8080")
    }

    /// Opens the verification link the Auth emulator "sent" to this email.
    private func verifyEmail(_ email: String) async throws {
        let host = try #require(emulatorHost)
        let projectID = try #require(Firestore.firestore().app.options.projectID)
        let listURL = URL(string: "http://\(host):9099/emulator/v1/projects/\(projectID)/oobCodes")!
        let (data, _) = try await URLSession.shared.data(from: listURL)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let codes = try #require(json["oobCodes"] as? [[String: Any]])
        let match = try #require(codes.last { ($0["email"] as? String) == email && ($0["requestType"] as? String) == "VERIFY_EMAIL" })
        let link = try #require(match["oobLink"] as? String)
        _ = try await URLSession.shared.data(from: try #require(URL(string: link)))
    }

    private func freshEmail(_ domain: String = "unc.edu") -> String {
        "it-\(UUID().uuidString.prefix(8).lowercased())@\(domain)"
    }

    private func freshHandle() -> String {
        "h_\(UUID().uuidString.prefix(8).lowercased().replacingOccurrences(of: "-", with: ""))"
    }

    @Test func signUpVerifyAndClaimAHandleEndToEnd() async throws {
        try requireEmulator()
        let email = freshEmail()
        let handle = freshHandle()

        let created = try await backend.createUser(email: email, password: "password1", displayName: "Pat Example")
        #expect(!created.isEmailVerified)
        #expect(created.displayName == "Pat Example")

        // Rules block an unverified account from reading profiles.
        await #expect(throws: AuthError.permissionDenied) {
            _ = try await backend.fetchProfile(uid: created.uid)
        }

        try await backend.sendVerificationEmail()
        try await verifyEmail(email)
        let verified = try #require(try await backend.reloadUser())
        #expect(verified.isEmailVerified)

        #expect(try await backend.fetchProfile(uid: verified.uid) == nil)
        #expect(try await backend.isHandleAvailable(handle))
        try await backend.createProfile(uid: verified.uid, displayName: "Pat Example", handle: handle)
        #expect(try await backend.fetchProfile(uid: verified.uid) == ProfileData(displayName: "Pat Example", handle: handle))
        #expect(try await !backend.isHandleAvailable(handle))
    }

    @Test func aSecondStudentCannotTakeTheSameHandle() async throws {
        try requireEmulator()
        let handle = freshHandle()

        let first = try await backend.createUser(email: freshEmail(), password: "password1", displayName: "First")
        try await backend.sendVerificationEmail()
        try await verifyEmail(first.email)
        _ = try await backend.reloadUser()
        try await backend.createProfile(uid: first.uid, displayName: "First", handle: handle)
        try backend.signOut()

        let second = try await backend.createUser(email: freshEmail(), password: "password1", displayName: "Second")
        try await backend.sendVerificationEmail()
        try await verifyEmail(second.email)
        _ = try await backend.reloadUser()
        await #expect(throws: AuthError.handleTaken) {
            try await backend.createProfile(uid: second.uid, displayName: "Second", handle: handle)
        }
        try backend.signOut()
    }

    @Test func aVerifiedNonUNCAccountIsBlockedByTheRulesEvenIfTheAppIsBypassed() async throws {
        try requireEmulator()
        // Auth itself does not restrict domains; the rules are the real gate.
        let outsider = try await backend.createUser(email: freshEmail("gmail.com"), password: "password1", displayName: "Out Sider")
        try await backend.sendVerificationEmail()
        try await verifyEmail(outsider.email)
        _ = try await backend.reloadUser()
        await #expect(throws: AuthError.permissionDenied) {
            try await backend.createProfile(uid: outsider.uid, displayName: "Out Sider", handle: freshHandle())
        }
        try backend.signOut()
    }

    @Test func wrongPasswordMapsToTheAppsOwnError() async throws {
        try requireEmulator()
        let email = freshEmail()
        _ = try await backend.createUser(email: email, password: "password1", displayName: "Pat")
        try backend.signOut()
        await #expect(throws: AuthError.wrongCredentials) {
            _ = try await backend.signIn(email: email, password: "not-the-password")
        }
        await #expect(throws: AuthError.emailInUse) {
            _ = try await backend.createUser(email: email, password: "password1", displayName: "Pat")
        }
    }
}
