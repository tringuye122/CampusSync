//
//  MockAuthBackend.swift
//  CampusSync
//
//  In-memory AuthBackend for previews and unit tests. Behaves like the real one:
//  email must be verified, handles are unique, and `reloadUser` picks up a
//  verification that the test performed with `markVerified`.
//

import Foundation

final class MockAuthBackend: AuthBackend {
    struct Account {
        var uid: String
        var email: String
        var password: String
        var displayName: String
        var isVerified: Bool
    }

    private(set) var accounts: [String: Account] = [:]      // keyed by email
    private(set) var profiles: [String: ProfileData] = [:]  // keyed by uid
    private(set) var handles: [String: String] = [:]        // handle -> uid
    private(set) var verificationEmailsSent = 0
    private var currentEmail: String?

    /// Set to make network calls fail, like being offline.
    var isOffline = false

    init(signedInEmail: String? = nil) {
        currentEmail = signedInEmail
    }

    /// Simulates the student tapping the link in the verification email.
    func markVerified(email: String) {
        accounts[email]?.isVerified = true
    }

    /// Seeds an existing, verified, fully set up student.
    func seed(email: String, password: String, displayName: String, handle: String) {
        let uid = "uid-\(accounts.count + 1)"
        accounts[email] = Account(uid: uid, email: email, password: password, displayName: displayName, isVerified: true)
        profiles[uid] = ProfileData(displayName: displayName, handle: handle)
        handles[handle] = uid
    }

    private func user(_ account: Account) -> BackendUser {
        BackendUser(uid: account.uid, email: account.email, displayName: account.displayName,
                    isEmailVerified: account.isVerified)
    }

    private func requireOnline() throws {
        if isOffline { throw AuthError.network }
    }

    func currentUser() -> BackendUser? {
        currentEmail.flatMap { accounts[$0] }.map(user)
    }

    func createUser(email: String, password: String, displayName: String) async throws -> BackendUser {
        try requireOnline()
        guard accounts[email] == nil else { throw AuthError.emailInUse }
        let account = Account(
            uid: "uid-\(accounts.count + 1)", email: email, password: password,
            displayName: displayName, isVerified: false)
        accounts[email] = account
        currentEmail = email
        return user(account)
    }

    func signIn(email: String, password: String) async throws -> BackendUser {
        try requireOnline()
        guard let account = accounts[email], account.password == password else { throw AuthError.wrongCredentials }
        currentEmail = email
        return user(account)
    }

    func signOut() throws {
        currentEmail = nil
    }

    func sendVerificationEmail() async throws {
        try requireOnline()
        verificationEmailsSent += 1
    }

    func reloadUser() async throws -> BackendUser? {
        try requireOnline()
        return currentUser()
    }

    func sendPasswordReset(email: String) async throws {
        try requireOnline()
    }

    func fetchProfile(uid: String) async throws -> ProfileData? {
        try requireOnline()
        return profiles[uid]
    }

    func isHandleAvailable(_ handle: String) async throws -> Bool {
        try requireOnline()
        return handles[handle] == nil
    }

    func createProfile(uid: String, displayName: String, handle: String) async throws {
        try requireOnline()
        guard handles[handle] == nil else { throw AuthError.handleTaken }
        handles[handle] = uid
        profiles[uid] = ProfileData(displayName: displayName, handle: handle)
    }
}
