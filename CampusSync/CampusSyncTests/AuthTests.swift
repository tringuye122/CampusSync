//
//  AuthTests.swift
//  CampusSyncTests
//
//  Sign-in rules and the AuthService state machine, against MockAuthBackend.
//  No Firebase and no network.
//

import Foundation
import Testing
@testable import CampusSync

@MainActor
struct AuthTests {
    // MARK: Validator

    @Test func onlyUNCEmailsAreAccepted() {
        #expect(AuthValidator.emailIssue("pat@unc.edu") == nil)
        #expect(AuthValidator.emailIssue("  Pat.Example@UNC.EDU ") == nil)
        #expect(AuthValidator.emailIssue("pat@gmail.com") == .notUNCEmail)
        #expect(AuthValidator.emailIssue("pat@unc.edu.evil.com") == .notUNCEmail)
        #expect(AuthValidator.emailIssue("pat@notunc.edu") == .notUNCEmail)
        #expect(AuthValidator.emailIssue("not an email") == .invalidEmail)
        #expect(AuthValidator.emailIssue("") == .invalidEmail)
    }

    @Test func handleRules() {
        #expect(AuthValidator.normalizeHandle("  @Pat_99 ") == "pat_99")
        #expect(AuthValidator.handleIssue("pat_99") == nil)
        #expect(AuthValidator.handleIssue("@pat") == nil)
        #expect(AuthValidator.handleIssue("ab") != nil)                       // too short
        #expect(AuthValidator.handleIssue(String(repeating: "a", count: 21)) != nil)  // too long
        #expect(AuthValidator.handleIssue("pat.example") != nil)              // dot not allowed
        #expect(AuthValidator.handleIssue("pat example") != nil)
        #expect(AuthValidator.handleIssue("pat-x") != nil)
    }

    @Test func nameAndPasswordRules() {
        #expect(AuthValidator.displayNameIssue("Pat Example") == nil)
        #expect(AuthValidator.displayNameIssue("P") != nil)
        #expect(AuthValidator.displayNameIssue(String(repeating: "a", count: 41)) != nil)
        #expect(AuthValidator.normalizedName("  Pat   Example ") == "Pat Example")
        #expect(AuthValidator.passwordIssue("1234567") == .weakPassword)
        #expect(AuthValidator.passwordIssue("12345678") == nil)
    }

    // MARK: Service

    private func makeService(
        _ backend: MockAuthBackend = MockAuthBackend()
    ) -> (AuthService, MockAuthBackend) {
        let defaults = UserDefaults(suiteName: "auth-tests-\(UUID().uuidString)")!
        return (AuthService(backend: backend, defaults: defaults), backend)
    }

    @Test func noSavedSessionMeansSignedOut() async {
        let (auth, _) = makeService()
        #expect(auth.state == .loading)
        await auth.refresh()
        #expect(auth.state == .signedOut)
    }

    @Test func fullSignUpFlowEndsSignedIn() async {
        let (auth, backend) = makeService()

        await auth.signUp(email: "Pat@UNC.edu", password: "password1", displayName: "Pat Example")
        #expect(auth.errorMessage == nil)
        #expect(auth.state == .needsVerification(email: "pat@unc.edu"))
        #expect(backend.verificationEmailsSent == 1)

        // Tapping "I've verified" before opening the link keeps them waiting.
        await auth.confirmVerification()
        #expect(auth.state == .needsVerification(email: "pat@unc.edu"))
        #expect(auth.infoMessage != nil)

        backend.markVerified(email: "pat@unc.edu")
        await auth.confirmVerification()
        #expect(auth.state == .needsProfile(email: "pat@unc.edu", suggestedName: "Pat Example"))

        await auth.createProfile(displayName: "Pat Example", handle: "@Pat")
        guard case .signedIn(let account) = auth.state else {
            Issue.record("Expected signedIn, got \(auth.state)")
            return
        }
        #expect(account.handle == "pat")
        #expect(account.email == "pat@unc.edu")
        #expect(account.displayName == "Pat Example")
    }

    @Test func nonUNCSignUpIsRejectedBeforeAnyAccountIsCreated() async {
        let (auth, backend) = makeService()
        await auth.signUp(email: "pat@gmail.com", password: "password1", displayName: "Pat")
        #expect(auth.errorMessage == AuthError.notUNCEmail.message)
        #expect(auth.state == .loading)   // nothing happened
        #expect(backend.accounts.isEmpty)
    }

    @Test func weakPasswordAndBadNameAreRejected() async {
        let (auth, backend) = makeService()
        await auth.signUp(email: "pat@unc.edu", password: "short", displayName: "Pat")
        #expect(auth.errorMessage == AuthError.weakPassword.message)
        await auth.signUp(email: "pat@unc.edu", password: "password1", displayName: "P")
        #expect(auth.errorMessage != nil)
        #expect(backend.accounts.isEmpty)
    }

    @Test func existingStudentSignsInStraightToTheApp() async {
        let backend = MockAuthBackend()
        backend.seed(email: "pat@unc.edu", password: "password1", displayName: "Pat Example", handle: "pat")
        let (auth, _) = makeService(backend)

        await auth.signIn(email: "pat@unc.edu", password: "password1")
        #expect(auth.account?.handle == "pat")
    }

    @Test func wrongPasswordShowsAGenericMessage() async {
        let backend = MockAuthBackend()
        backend.seed(email: "pat@unc.edu", password: "password1", displayName: "Pat", handle: "pat")
        let (auth, _) = makeService(backend)

        await auth.signIn(email: "pat@unc.edu", password: "nope")
        #expect(auth.errorMessage == AuthError.wrongCredentials.message)
        #expect(auth.account == nil)
    }

    @Test func takenHandleIsReportedAndLeavesTheProfileSetupOpen() async {
        let backend = MockAuthBackend()
        backend.seed(email: "first@unc.edu", password: "password1", displayName: "First", handle: "pat")
        let (auth, _) = makeService(backend)

        await auth.signUp(email: "second@unc.edu", password: "password1", displayName: "Second")
        backend.markVerified(email: "second@unc.edu")
        await auth.confirmVerification()

        #expect(await auth.checkHandle("pat") == .taken)
        #expect(await auth.checkHandle("fresh_handle") == .available)
        #expect({ if case .invalid = $0 { true } else { false } }(await auth.checkHandle("a!")))

        await auth.createProfile(displayName: "Second", handle: "pat")
        #expect(auth.errorMessage == AuthError.handleTaken.message)
        #expect(auth.account == nil)
    }

    @Test func signOutReturnsToSignedOut() async {
        let backend = MockAuthBackend()
        backend.seed(email: "pat@unc.edu", password: "password1", displayName: "Pat", handle: "pat")
        let (auth, _) = makeService(backend)
        await auth.signIn(email: "pat@unc.edu", password: "password1")
        auth.signOut()
        #expect(auth.state == .signedOut)
        await auth.refresh()
        #expect(auth.state == .signedOut)
    }

    @Test func offlineLaunchKeepsASetUpStudentSignedInFromTheCache() async {
        let backend = MockAuthBackend()
        backend.seed(email: "pat@unc.edu", password: "password1", displayName: "Pat", handle: "pat")
        let (auth, _) = makeService(backend)
        await auth.signIn(email: "pat@unc.edu", password: "password1")   // online: caches the account

        backend.isOffline = true
        await auth.refresh()
        #expect(auth.account?.handle == "pat")
    }

    @Test func offlineWithNoCacheShowsAConnectionProblemNotProfileSetup() async {
        let backend = MockAuthBackend(signedInEmail: "pat@unc.edu")
        backend.seed(email: "pat@unc.edu", password: "password1", displayName: "Pat", handle: "pat")
        backend.isOffline = true
        let (auth, _) = makeService(backend)

        await auth.refresh()
        #expect(auth.state == .connectionProblem(email: "pat@unc.edu"))
    }

    @Test func signUpWithExistingEmailExplainsWhatToDo() async {
        let backend = MockAuthBackend()
        backend.seed(email: "pat@unc.edu", password: "password1", displayName: "Pat", handle: "pat")
        let (auth, _) = makeService(backend)
        await auth.signUp(email: "pat@unc.edu", password: "password1", displayName: "Pat")
        #expect(auth.errorMessage == AuthError.emailInUse.message)
    }
}
