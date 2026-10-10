//
//  AuthBackend.swift
//  CampusSync
//
//  The seam between the app's sign-in logic and Firebase. AuthService only talks
//  to this protocol, so the whole flow is unit-tested with MockAuthBackend and
//  Firebase stays isolated in FirebaseAuthBackend.
//

import Foundation

protocol AuthBackend {
    /// The currently signed-in Firebase user, if any (restored from the keychain at launch).
    func currentUser() -> BackendUser?
    func createUser(email: String, password: String, displayName: String) async throws -> BackendUser
    func signIn(email: String, password: String) async throws -> BackendUser
    func signOut() throws
    func sendVerificationEmail() async throws
    /// Re-reads the user and refreshes the ID token so Firestore rules see `email_verified`.
    func reloadUser() async throws -> BackendUser?
    func sendPasswordReset(email: String) async throws

    /// The `users/{uid}` profile, or nil if the student hasn't picked a handle yet.
    func fetchProfile(uid: String) async throws -> ProfileData?
    func isHandleAvailable(_ handle: String) async throws -> Bool
    /// Claims the handle and creates the profile together. Throws `AuthError.handleTaken`.
    func createProfile(uid: String, displayName: String, handle: String) async throws
}
