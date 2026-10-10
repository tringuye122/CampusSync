//
//  AuthModels.swift
//  CampusSync
//
//  Plain values and rules for accounts. Nothing here imports Firebase, so the
//  rules are unit-tested and the same checks are mirrored in firestore.rules.
//

import Foundation

/// The signed-in student as the app sees them.
struct UserAccount: Codable, Equatable, Sendable {
    var uid: String
    var email: String
    var displayName: String
    /// Lowercase, without the "@". Unique across all students.
    var handle: String
}

/// What Firebase Auth knows about the current user.
struct BackendUser: Equatable, Sendable {
    var uid: String
    var email: String
    var displayName: String?
    var isEmailVerified: Bool
}

/// The Firestore profile document (`users/{uid}`). It deliberately has no email.
struct ProfileData: Equatable, Sendable {
    var displayName: String
    var handle: String
}

enum AuthError: Error, Equatable {
    case notUNCEmail
    case invalidEmail
    case weakPassword
    case emailInUse
    case wrongCredentials
    case tooManyRequests
    case network
    case handleTaken
    case permissionDenied
    case invalidInput(String)
    case unknown

    /// Text safe to show a student.
    var message: String {
        switch self {
        case .notUNCEmail: "Use your @unc.edu email address."
        case .invalidEmail: "That doesn't look like a valid email address."
        case .weakPassword: "Choose a stronger password (at least 8 characters)."
        case .emailInUse: "An account with that email already exists. Try signing in."
        case .wrongCredentials: "That email or password is incorrect."
        case .tooManyRequests: "Too many attempts. Wait a moment and try again."
        case .network: "Couldn't reach the server. Check your connection and try again."
        case .handleTaken: "That handle is already taken."
        case .permissionDenied: "You don't have permission to do that. Verify your email and try again."
        case .invalidInput(let reason): reason
        case .unknown: "Something went wrong. Please try again."
        }
    }
}

/// Input rules. The same limits are enforced again by Firestore security rules,
/// because the client alone is never trusted.
nonisolated enum AuthValidator {
    static let allowedEmailSuffix = "@unc.edu"
    static let minPasswordLength = 8
    static let displayNameLength = 2...40
    static let handleLength = 3...20

    static func normalizedEmail(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Nil when the email is acceptable.
    static func emailIssue(_ raw: String) -> AuthError? {
        let email = normalizedEmail(raw)
        guard email.range(of: #"^[^@\s]+@[^@\s]+\.[^@\s]+$"#, options: .regularExpression) != nil else {
            return .invalidEmail
        }
        return email.hasSuffix(allowedEmailSuffix) ? nil : .notUNCEmail
    }

    static func passwordIssue(_ password: String) -> AuthError? {
        password.count >= minPasswordLength ? nil : .weakPassword
    }

    static func normalizedName(_ raw: String) -> String {
        raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func displayNameIssue(_ raw: String) -> AuthError? {
        displayNameLength.contains(normalizedName(raw).count)
            ? nil
            : .invalidInput("Your name must be \(displayNameLength.lowerBound) to \(displayNameLength.upperBound) characters.")
    }

    /// Lowercased, trimmed, with a leading "@" removed.
    static func normalizeHandle(_ raw: String) -> String {
        var handle = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if handle.hasPrefix("@") { handle.removeFirst() }
        return handle
    }

    static func handleIssue(_ raw: String) -> AuthError? {
        let handle = normalizeHandle(raw)
        let isValid = handleLength.contains(handle.count)
            && handle.range(of: #"^[a-z0-9_]+$"#, options: .regularExpression) != nil
        return isValid
            ? nil
            : .invalidInput("Handles are \(handleLength.lowerBound) to \(handleLength.upperBound) characters: lowercase letters, numbers and underscores.")
    }
}
