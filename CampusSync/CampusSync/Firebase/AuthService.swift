//
//  AuthService.swift
//  CampusSync
//
//  Owns who is signed in and which screen the app should show:
//
//    signedOut -> (sign up or sign in) -> needsVerification -> needsProfile -> signedIn
//
//  Email and password, restricted to verified @unc.edu addresses. Views read
//  `state`; actions set `errorMessage` instead of throwing.
//

import Foundation
import Observation

@Observable
final class AuthService {
    enum State: Equatable {
        /// Checking for a saved session at launch.
        case loading
        case signedOut
        /// Account exists but the email isn't verified yet.
        case needsVerification(email: String)
        /// Verified, but no handle/profile yet.
        case needsProfile(email: String, suggestedName: String)
        /// Verified and signed in, but the profile couldn't be loaded (offline, nothing cached).
        case connectionProblem(email: String)
        case signedIn(UserAccount)
    }

    enum HandleAvailability: Equatable {
        case unchecked, checking, available, taken, invalid(String), unknown
    }

    private(set) var state: State = .loading
    private(set) var isBusy = false
    var errorMessage: String?
    var infoMessage: String?

    private let backend: AuthBackend
    private let defaults: UserDefaults

    init(backend: AuthBackend, defaults: UserDefaults = .standard) {
        self.backend = backend
        self.defaults = defaults
    }

    var account: UserAccount? {
        if case .signedIn(let account) = state { return account }
        return nil
    }

    // MARK: Launch and refresh

    /// Decides what to show from the saved Firebase session. Safe to call repeatedly,
    /// e.g. at launch, when the app foregrounds, and after the student verifies their email.
    func refresh() async {
        guard var user = backend.currentUser() else {
            state = .signedOut
            return
        }

        if !user.isEmailVerified, let reloaded = try? await backend.reloadUser() {
            user = reloaded   // picks up verification done in the mail app or browser
        }
        guard user.isEmailVerified else {
            state = .needsVerification(email: user.email)
            return
        }

        do {
            if let profile = try await backend.fetchProfile(uid: user.uid) {
                let account = UserAccount(
                    uid: user.uid, email: user.email, displayName: profile.displayName, handle: profile.handle)
                saveCachedAccount(account)
                state = .signedIn(account)
            } else {
                state = .needsProfile(email: user.email, suggestedName: user.displayName ?? "")
            }
        } catch {
            // Offline: a student who already finished setup stays signed in from the cache.
            if let cached = cachedAccount(uid: user.uid) {
                state = .signedIn(cached)
            } else {
                state = .connectionProblem(email: user.email)
            }
        }
    }

    // MARK: Actions

    func signUp(email: String, password: String, displayName: String) async {
        if let issue = AuthValidator.emailIssue(email)
            ?? AuthValidator.displayNameIssue(displayName)
            ?? AuthValidator.passwordIssue(password) {
            errorMessage = issue.message
            return
        }
        await perform {
            _ = try await self.backend.createUser(
                email: AuthValidator.normalizedEmail(email), password: password,
                displayName: AuthValidator.normalizedName(displayName))
            do {
                try await self.backend.sendVerificationEmail()
            } catch {
                self.errorMessage = "Your account was created, but the verification email couldn't be sent. Tap Resend."
            }
            await self.refresh()
        }
    }

    func signIn(email: String, password: String) async {
        if let issue = AuthValidator.emailIssue(email) {
            errorMessage = issue.message
            return
        }
        await perform {
            _ = try await self.backend.signIn(email: AuthValidator.normalizedEmail(email), password: password)
            await self.refresh()
        }
    }

    func resendVerification() async {
        await perform {
            try await self.backend.sendVerificationEmail()
            self.infoMessage = "Verification email sent. Check your inbox and spam folder."
        }
    }

    /// "I've verified": re-checks with the server.
    func confirmVerification() async {
        await perform {
            _ = try await self.backend.reloadUser()
            await self.refresh()
            if case .needsVerification = self.state {
                self.infoMessage = "Not verified yet. Open the link in the email first."
            }
        }
    }

    func sendPasswordReset(email: String) async {
        if let issue = AuthValidator.emailIssue(email) {
            errorMessage = issue.message
            return
        }
        await perform {
            try await self.backend.sendPasswordReset(email: AuthValidator.normalizedEmail(email))
            self.infoMessage = "If an account exists for that email, a reset link is on its way."
        }
    }

    /// Whether `raw` can be claimed, for live feedback while typing.
    func checkHandle(_ raw: String) async -> HandleAvailability {
        if let issue = AuthValidator.handleIssue(raw) {
            if case .invalidInput(let reason) = issue { return .invalid(reason) }
            return .invalid(issue.message)
        }
        do {
            return try await backend.isHandleAvailable(AuthValidator.normalizeHandle(raw)) ? .available : .taken
        } catch {
            return .unknown
        }
    }

    func createProfile(displayName: String, handle: String) async {
        if let issue = AuthValidator.displayNameIssue(displayName) ?? AuthValidator.handleIssue(handle) {
            errorMessage = issue.message
            return
        }
        guard let user = backend.currentUser() else {
            state = .signedOut
            return
        }
        await perform {
            try await self.backend.createProfile(
                uid: user.uid, displayName: AuthValidator.normalizedName(displayName),
                handle: AuthValidator.normalizeHandle(handle))
            await self.refresh()
        }
    }

    func signOut() {
        do {
            try backend.signOut()
        } catch {
            errorMessage = AuthError.unknown.message
            return
        }
        clearMessages()
        state = .signedOut
    }

    func clearMessages() {
        errorMessage = nil
        infoMessage = nil
    }

    // MARK: Helpers

    /// Runs an action with a busy flag and turns thrown errors into `errorMessage`.
    private func perform(_ action: @escaping () async throws -> Void) async {
        isBusy = true
        clearMessages()
        defer { isBusy = false }
        do {
            try await action()
        } catch let error as AuthError {
            errorMessage = error.message
        } catch {
            errorMessage = AuthError.unknown.message
        }
    }

    private func cacheKey(_ uid: String) -> String { "account.\(uid)" }

    private func saveCachedAccount(_ account: UserAccount) {
        if let data = try? JSONEncoder().encode(account) {
            defaults.set(data, forKey: cacheKey(account.uid))
        }
    }

    private func cachedAccount(uid: String) -> UserAccount? {
        defaults.data(forKey: cacheKey(uid)).flatMap { try? JSONDecoder().decode(UserAccount.self, from: $0) }
    }
}
