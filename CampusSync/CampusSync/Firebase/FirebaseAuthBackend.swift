//
//  FirebaseAuthBackend.swift
//  CampusSync
//
//  The real AuthBackend: Firebase Auth for accounts, Firestore for the profile
//  and unique handle. This is the only auth file that imports Firebase.
//
//  Firestore layout used here (rules in firebase/firestore.rules):
//    users/{uid}      displayName, handle, createdAt     (no email, readable by verified students)
//    handles/{handle} uid                                 (create-only, so handles stay unique)
//

import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import Foundation

final class FirebaseAuthBackend: AuthBackend {
    private var auth: Auth { Auth.auth() }
    private var db: Firestore { Firestore.firestore() }

    // MARK: Auth

    func currentUser() -> BackendUser? {
        auth.currentUser.map(Self.backendUser)
    }

    func createUser(email: String, password: String, displayName: String) async throws -> BackendUser {
        do {
            let result = try await auth.createUser(withEmail: email, password: password)
            let change = result.user.createProfileChangeRequest()
            change.displayName = displayName
            try? await change.commitChanges()   // the name is also collected again at profile setup
            return Self.backendUser(result.user)
        } catch {
            throw Self.map(error)
        }
    }

    func signIn(email: String, password: String) async throws -> BackendUser {
        do {
            return Self.backendUser(try await auth.signIn(withEmail: email, password: password).user)
        } catch {
            throw Self.map(error)
        }
    }

    func signOut() throws {
        try auth.signOut()
    }

    func sendVerificationEmail() async throws {
        guard let user = auth.currentUser else { throw AuthError.unknown }
        do {
            try await user.sendEmailVerification()
        } catch {
            throw Self.map(error)
        }
    }

    func reloadUser() async throws -> BackendUser? {
        guard let user = auth.currentUser else { return nil }
        do {
            try await user.reload()
            // Firestore rules read `email_verified` from the ID token, which only
            // updates when the token is refreshed.
            _ = try await user.getIDTokenResult(forcingRefresh: true)
            return auth.currentUser.map(Self.backendUser)
        } catch {
            throw Self.map(error)
        }
    }

    func sendPasswordReset(email: String) async throws {
        do {
            try await auth.sendPasswordReset(withEmail: email)
        } catch {
            throw Self.map(error)
        }
    }

    // MARK: Profile and handles

    func fetchProfile(uid: String) async throws -> ProfileData? {
        do {
            let snapshot = try await db.collection("users").document(uid).getDocument()
            guard snapshot.exists,
                  let data = snapshot.data(),
                  let name = data["displayName"] as? String,
                  let handle = data["handle"] as? String
            else { return nil }
            return ProfileData(displayName: name, handle: handle)
        } catch {
            throw Self.map(error)
        }
    }

    func isHandleAvailable(_ handle: String) async throws -> Bool {
        do {
            return try await !db.collection("handles").document(handle).getDocument().exists
        } catch {
            throw Self.map(error)
        }
    }

    func createProfile(uid: String, displayName: String, handle: String) async throws {
        let handleRef = db.collection("handles").document(handle)
        let userRef = db.collection("users").document(uid)

        if try await !isHandleAvailable(handle) { throw AuthError.handleTaken }

        // One atomic batch: the rules check that the handle doc and the profile agree.
        let batch = db.batch()
        batch.setData(["uid": uid], forDocument: handleRef)
        batch.setData([
            "displayName": displayName,
            "handle": handle,
            "createdAt": FieldValue.serverTimestamp(),
        ], forDocument: userRef)

        do {
            try await batch.commit()
        } catch {
            // Someone may have claimed it between our check and the commit.
            if (try? await isHandleAvailable(handle)) == false { throw AuthError.handleTaken }
            throw Self.map(error)
        }
    }

    // MARK: Mapping

    private static func backendUser(_ user: User) -> BackendUser {
        BackendUser(uid: user.uid, email: user.email ?? "", displayName: user.displayName,
                    isEmailVerified: user.isEmailVerified)
    }

    /// Turns Firebase errors into the app's own, so no Firebase types leak out.
    static func map(_ error: Error) -> AuthError {
        if let known = error as? AuthError { return known }
        let ns = error as NSError

        if ns.domain == AuthErrors.domain, let code = AuthErrorCode(rawValue: ns.code) {
            switch code {
            case .emailAlreadyInUse: return .emailInUse
            case .invalidEmail: return .invalidEmail
            case .weakPassword: return .weakPassword
            case .wrongPassword, .invalidCredential, .userNotFound: return .wrongCredentials
            case .networkError: return .network
            case .tooManyRequests: return .tooManyRequests
            default: return .unknown
            }
        }
        if ns.domain == FirestoreErrorDomain, let code = FirestoreErrorCode.Code(rawValue: ns.code) {
            switch code {
            case .unavailable, .deadlineExceeded: return .network
            case .permissionDenied: return .permissionDenied
            default: return .unknown
            }
        }
        if ns.domain == NSURLErrorDomain { return .network }
        return .unknown
    }
}

/// Opt-in local emulators for development, so nothing touches the real project.
/// Set the environment variable `FIREBASE_EMULATOR_HOST` (e.g. `localhost`) in the
/// Xcode scheme, then start the emulators with `firebase emulators:start`. Debug builds only.
enum FirebaseEmulator {
    static func configureIfRequested() {
        #if DEBUG
        guard let host = ProcessInfo.processInfo.environment["FIREBASE_EMULATOR_HOST"], !host.isEmpty else { return }
        Auth.auth().useEmulator(withHost: host, port: 9099)
        let firestore = Firestore.firestore()
        firestore.useEmulator(withHost: host, port: 8080)
        // useEmulator only sets the host; the emulator speaks plain HTTP, so TLS must be off.
        let settings = firestore.settings
        settings.isSSLEnabled = false
        firestore.settings = settings
        #endif
    }
}
