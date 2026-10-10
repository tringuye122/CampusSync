//
//  FriendModels.swift
//  CampusSync
//
//  Plain values for the friend graph. Nothing here imports Firebase. These are new
//  types (not SwiftData models), so Models.swift stays untouched.
//
//  Firestore layout (rules in firebase/firestore.rules):
//    friendRequests/{fromUID}_{toUID}  fromUID, toUID, status, createdAt
//    users/{uid}/friends/{friendUID}   since     (written for both people when a request is accepted)
//

import Foundation

/// A student as shown in search results, request rows and the friends list.
/// Only a name and a handle: the public profile, never an email.
struct FriendSummary: Identifiable, Equatable, Hashable, Sendable {
    var id: String          // Firebase uid
    var displayName: String
    /// Lowercase, without the "@".
    var handle: String
}

enum FriendRequestStatus: String, Sendable {
    case pending, accepted, declined
}

struct FriendRequest: Identifiable, Equatable, Sendable {
    /// "{fromUID}_{toUID}", which is also the Firestore document id.
    var id: String { Self.makeID(from: fromUID, to: toUID) }
    var fromUID: String
    var toUID: String
    var status: FriendRequestStatus
    var createdAt: Date?
    /// The person on the other end from the signed-in user's point of view.
    var other: FriendSummary

    static func makeID(from: String, to: String) -> String { "\(from)_\(to)" }
}

enum FriendError: Error, Equatable {
    case notSignedIn
    case invalidHandle
    case handleNotFound
    case cannotAddSelf
    case alreadyFriends
    case requestPending
    case requestGone
    case offline
    case permissionDenied
    case unknown

    /// Text safe to show a student.
    var message: String {
        switch self {
        case .notSignedIn: "Sign in to add friends."
        case .invalidHandle: "Handles use letters, numbers and underscores."
        case .handleNotFound: "No student has that handle."
        case .cannotAddSelf: "That's you!"
        case .alreadyFriends: "You're already friends."
        case .requestPending: "A request is already waiting."
        case .requestGone: "That request is no longer available. It may have been cancelled."
        case .offline: "Couldn't reach the server. Check your connection and try again."
        case .permissionDenied: "That isn't allowed right now. Pull down to refresh and try again."
        case .unknown: "Something went wrong. Please try again."
        }
    }
}

/// Limits for searching students by handle as you type.
enum FriendSearch {
    /// A single letter would list too many students, so searching starts at two characters.
    static let minimumLength = 2
    static let maxResults = 10

    /// Handles are lowercase letters, digits and underscores (see AuthValidator and the rules).
    static func isValidPrefix(_ prefix: String) -> Bool {
        prefix.range(of: "^[a-z0-9_]{1,20}$", options: .regularExpression) != nil
    }
}
