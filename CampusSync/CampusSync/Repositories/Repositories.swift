//
//  Repositories.swift
//  CampusSync
//
//  Views and ViewModels talk only to these protocols, never to SwiftData or
//  Firestore. Methods are async throws because the Firestore implementations need it.
//  Writes here do not touch the widget; ViewModels rewrite the snapshot and reload
//  timelines after a successful write.
//

import Foundation

enum RepositoryError: Error {
    case notSeeded
    case notFound
    case inviteFull
    case notDuesClub
    /// Posting an event needs membership in that club.
    case notMember
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
    /// Throws `ScheduleSharingError.notConfirmed` when the choice is saved on this phone but the
    /// server has not confirmed it (offline): it applies when the connection returns.
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
    /// Reset: deletes every invite the user hosts (expired or not) and takes the user off the
    /// guest list of invites they were invited to.
    @discardableResult
    func removeMyInvitesAndRSVPs() async throws -> InviteReset
}

/// What a reset removed, so the Firestore repository can mirror it on the server.
struct InviteReset: Equatable {
    var deletedInviteIDs: [String] = []
    var leftInviteIDs: [String] = []
}

struct ClubReset: Equatable {
    /// (event id, club id) of events the user posted.
    var deletedEvents: [DeletedEvent] = []
    var leftClubIDs: [String] = []

    struct DeletedEvent: Equatable {
        var eventID: String
        var clubID: String
    }
}

protocol ClubRepository {
    func clubs() async throws -> [Club]
    /// Upcoming events, soonest first.
    func events(now: Date) async throws -> [ClubEvent]
    /// Joining also subscribes the user to notifications for that club.
    func joinClub(id: String) async throws
    /// One tap: flips local state and marks the profile a Verified Member. No real payment.
    func payDues(clubID: String) async throws
    /// Leaving removes the membership; leaving a dues club also clears the dues-paid state
    /// (and so the Verified Member badge, unless another dues club is still paid).
    func leaveClub(id: String) async throws
    /// Posts an event for a club the user has joined. The event takes the club's access and dues.
    @discardableResult
    func postEvent(_ draft: ClubEventDraft) async throws -> ClubEvent
    /// Removes an event the user posted.
    func deleteEvent(id: String) async throws
    /// Reset: deletes every event the user posted and leaves every club (which also clears dues
    /// paid and the Verified Member badge).
    @discardableResult
    func removeMyEventsAndMemberships() async throws -> ClubReset
}

enum ScheduleSharingError: Error, Equatable {
    case notConfirmed
}

/// What the Post sheet collects for a new club event.
struct ClubEventDraft: Equatable {
    var clubID: String
    var title: String
    var details = ""
    var location: String
    var start: Date
    var durationMinutes = 60

    var end: Date { start.addingTimeInterval(TimeInterval(durationMinutes * 60)) }
    /// The same limits the Firestore rules enforce.
    var isValid: Bool {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let place = location.trimmingCharacters(in: .whitespacesAndNewlines)
        // Counted in Unicode scalars, like the rules, so an emoji sequence cannot pass here and fail there.
        return !clubID.isEmpty && (1...80).contains(name.unicodeScalars.count) && (1...60).contains(place.unicodeScalars.count)
            && details.unicodeScalars.count <= 300 && durationMinutes > 0
    }
}
