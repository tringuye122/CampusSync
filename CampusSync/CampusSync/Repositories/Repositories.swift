//
//  Repositories.swift
//  CampusSync
//
//  Views and ViewModels talk only to these protocols, never to SwiftData or
//  Firestore. Methods are async throws so a Firestore implementation can swap in
//  later. Writes here do not touch the widget; ViewModels rewrite the snapshot
//  and reload timelines after a successful write.
//

import Foundation

enum RepositoryError: Error {
    case notSeeded
    case notFound
    case inviteFull
    case notDuesClub
}

/// The signed-in user. One demo user in the MVP.
protocol UserRepository {
    func currentUser() async throws -> UserProfile
}

protocol ScheduleRepository {
    func classes() async throws -> [ClassSchedule]
    /// Replaces the whole schedule (used after the import review screen).
    func replaceClasses(with classes: [ClassSchedule]) async throws
    /// Same result as importing the sample PDF; the demo safety net.
    func loadDemoSchedule() async throws
    /// Only friends the user has added.
    func friends() async throws -> [FriendProfile]
    /// Whether class times (never titles or instructors) are shared with friends. On by default.
    var sharesScheduleWithFriends: Bool { get }
    /// Turning it off removes the shared times from the server; turning it on publishes them.
    func setSharesScheduleWithFriends(_ shares: Bool) async throws
    /// RateMyProfessors rating for an instructor (cached; works offline once fetched).
    func professorRating(for instructor: String) async -> ProfessorRatingLookup
}

protocol InviteRepository {
    /// Unexpired invites the user hosts or was invited to, soonest first.
    /// Expiry is filtered here at read time (now > expiresAt).
    func activeInvites(now: Date) async throws -> [OpenInvite]
    func post(_ invite: OpenInvite) async throws
    /// Adds or removes the current user as an attendee.
    func toggleRSVP(inviteID: String) async throws
}

protocol ClubRepository {
    func clubs() async throws -> [Club]
    /// Upcoming events, soonest first.
    func events(now: Date) async throws -> [ClubEvent]
    /// Joining also subscribes the user to notifications for that club.
    func joinClub(id: String) async throws
    /// One tap: flips local state and marks the profile a Verified Member. No real payment.
    func payDues(clubID: String) async throws
}
