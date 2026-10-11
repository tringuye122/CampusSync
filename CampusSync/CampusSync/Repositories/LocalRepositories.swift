//
//  LocalRepositories.swift
//  CampusSync
//
//  SwiftData-backed implementations of the repository protocols, seeded from
//  SampleData. Fully offline. They are the cache the Firestore repositories read and write,
//  and the previews', tests' and offline fallback.
//

import Foundation
import SwiftData

/// Seeds the local store.
extension ModelContext {
    /// The one cached student profile, or `notSeeded` when there is none (signed out).
    func currentUserProfile() throws -> UserProfile {
        guard let user = try fetch(FetchDescriptor<UserProfile>()).first else {
            throw RepositoryError.notSeeded
        }
        return user
    }
}

@MainActor
struct LocalDataStore {
    let context: ModelContext

    /// Inserts seed data only when the store is empty.
    func seedIfNeeded(now: Date) throws {
        guard try context.fetchCount(FetchDescriptor<UserProfile>()) == 0 else { return }
        try insertSeed(now: now)
    }

    /// Regenerates the time-relative seed content (invites and club events) when every
    /// invite has expired, e.g. reopening the app the next day. Keeps the user's
    /// schedule, friends, club membership and Verified Member state. Returns true if it refreshed.
    @discardableResult
    func refreshIfStale(now: Date) throws -> Bool {
        // Only the fictional demo cache is refreshed. A real account's cache holds real club
        // events and an empty invite list is normal; replacing those with seed data would be wrong.
        let users = try context.fetch(FetchDescriptor<UserProfile>())
        guard users.contains(where: { $0.id.hasPrefix("seed-") }) else { return false }
        let invites = try context.fetch(FetchDescriptor<OpenInvite>())
        guard invites.allSatisfy({ $0.isExpired(at: now) }) else { return false }

        try context.delete(model: OpenInvite.self)
        try context.delete(model: ClubEvent.self)
        SampleData.invites(now: now).forEach(context.insert)
        SampleData.events(now: now).forEach(context.insert)
        // RSVPs pointed at the invites we just removed.
        for user in try context.fetch(FetchDescriptor<UserProfile>()) {
            user.rsvpedInviteIDs = []
        }
        try context.save()
        return true
    }

    private func insertSeed(now: Date) throws {
        context.insert(SampleData.user())
        SampleData.classes().forEach(context.insert)
        SampleData.friends().forEach(context.insert)
        SampleData.invites(now: now).forEach(context.insert)
        SampleData.clubs().forEach(context.insert)
        SampleData.events(now: now).forEach(context.insert)
        try context.save()
    }
}

@MainActor
final class LocalUserRepository: UserRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func currentUser() async throws -> UserProfile { try context.currentUserProfile() }
}

@MainActor
final class LocalScheduleRepository: ScheduleRepository {
    private let context: ModelContext
    private let ratings: ProfessorRatingProvider

    init(context: ModelContext, ratings: ProfessorRatingProvider) {
        self.context = context
        self.ratings = ratings
    }

    func classes() async throws -> [ClassSchedule] {
        let all = try context.fetch(FetchDescriptor<ClassSchedule>())
        return all.sorted { ($0.startMinutes, $0.courseCode) < ($1.startMinutes, $1.courseCode) }
    }

    func replaceClasses(with classes: [ClassSchedule]) async throws {
        try context.delete(model: ClassSchedule.self)
        classes.forEach(context.insert)
        try context.save()
    }

    func loadDemoSchedule() async throws {
        try await replaceClasses(with: SampleData.classes())
    }

    func friends() async throws -> [FriendProfile] {
        let friendIDs = try currentUser().friendIDs
        let all = try context.fetch(FetchDescriptor<FriendProfile>(sortBy: [SortDescriptor(\.displayName)]))
        return all.filter { friendIDs.contains($0.id) }
    }

    var sharesScheduleWithFriends: Bool { ScheduleSharingSetting.isEnabled }

    /// Local only: there is nothing to publish without Firestore.
    func setSharesScheduleWithFriends(_ shares: Bool) async throws {
        ScheduleSharingSetting.setEnabled(shares)
    }

    func professorRating(for instructor: String) async -> ProfessorRatingLookup {
        await ratings.rating(for: instructor)
    }

    private func currentUser() throws -> UserProfile { try context.currentUserProfile() }
}

@MainActor
final class LocalInviteRepository: InviteRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func activeInvites(now: Date) async throws -> [OpenInvite] {
        let user = try currentUser()
        return try context.fetch(FetchDescriptor<OpenInvite>())
            .filter { !$0.isExpired(at: now) }
            .filter { $0.hostID == user.id || $0.recipientIDs.contains(user.id) }
            .sorted { $0.startTime < $1.startTime }
    }

    func post(_ invite: OpenInvite) async throws {
        context.insert(invite)
        try context.save()
    }

    func toggleRSVP(inviteID: String) async throws {
        let user = try currentUser()
        let invites = try context.fetch(FetchDescriptor<OpenInvite>(predicate: #Predicate { $0.id == inviteID }))
        guard let invite = invites.first else { throw RepositoryError.notFound }

        if invite.attendeeIDs.contains(user.id) {
            invite.attendeeIDs.removeAll { $0 == user.id }
            user.rsvpedInviteIDs.removeAll { $0 == inviteID }
        } else {
            guard invite.attendeeIDs.count < invite.capacity else { throw RepositoryError.inviteFull }
            invite.attendeeIDs.append(user.id)
            user.rsvpedInviteIDs.append(inviteID)
        }
        try context.save()
    }

    func removeMyInvitesAndRSVPs() async throws -> InviteReset {
        let user = try currentUser()
        var reset = InviteReset()
        for invite in try context.fetch(FetchDescriptor<OpenInvite>()) {
            if invite.hostID == user.id {
                reset.deletedInviteIDs.append(invite.id)
                context.delete(invite)
            } else if invite.attendeeIDs.contains(user.id) {
                reset.leftInviteIDs.append(invite.id)
                invite.attendeeIDs.removeAll { $0 == user.id }
            }
        }
        user.rsvpedInviteIDs = []
        try context.save()
        return reset
    }

    private func currentUser() throws -> UserProfile { try context.currentUserProfile() }
}

@MainActor
final class LocalClubRepository: ClubRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func clubs() async throws -> [Club] {
        try context.fetch(FetchDescriptor<Club>(sortBy: [SortDescriptor(\.name)]))
    }

    func events(now: Date) async throws -> [ClubEvent] {
        try context.fetch(FetchDescriptor<ClubEvent>(
            predicate: #Predicate { $0.startTime >= now },
            sortBy: [SortDescriptor(\.startTime)]
        ))
    }

    func joinClub(id: String) async throws {
        let user = try currentUser()
        guard try club(id: id) != nil else { throw RepositoryError.notFound }
        if !user.joinedClubIDs.contains(id) {
            user.joinedClubIDs.append(id)
        }
        try context.save()
    }

    func payDues(clubID: String) async throws {
        let user = try currentUser()
        guard let club = try club(id: clubID) else { throw RepositoryError.notFound }
        guard club.access == .duesRequired else { throw RepositoryError.notDuesClub }
        if !user.joinedClubIDs.contains(clubID) {
            user.joinedClubIDs.append(clubID)
        }
        user.isVerifiedMember = true
        try context.save()
    }

    func leaveClub(id: String) async throws {
        let user = try currentUser()
        user.joinedClubIDs.removeAll { $0 == id }
        // A joined dues club was joined by paying, so any dues club still joined keeps the badge.
        let remaining = Set(user.joinedClubIDs)
        let paidClubs = try context.fetch(FetchDescriptor<Club>()).filter { $0.access == .duesRequired && remaining.contains($0.id) }
        user.isVerifiedMember = !paidClubs.isEmpty
        try context.save()
    }

    @discardableResult
    func postEvent(_ draft: ClubEventDraft) async throws -> ClubEvent {
        let user = try currentUser()
        guard let club = try club(id: draft.clubID) else { throw RepositoryError.notFound }
        guard user.joinedClubIDs.contains(club.id) else { throw RepositoryError.notMember }
        let event = ClubEvent(
            clubID: club.id, clubName: club.name,
            title: draft.title.trimmingCharacters(in: .whitespacesAndNewlines),
            details: draft.details.trimmingCharacters(in: .whitespacesAndNewlines),
            location: draft.location.trimmingCharacters(in: .whitespacesAndNewlines),
            startTime: draft.start, endTime: draft.end,
            access: club.access, duesAmount: club.duesAmount, posterID: user.id)
        context.insert(event)
        try context.save()
        return event
    }

    func deleteEvent(id: String) async throws {
        let user = try currentUser()
        guard let event = try context.fetch(FetchDescriptor<ClubEvent>(predicate: #Predicate { $0.id == id })).first
        else { throw RepositoryError.notFound }
        guard event.posterID == user.id else { throw RepositoryError.notMember }
        context.delete(event)
        try context.save()
    }

    func removeMyEventsAndMemberships() async throws -> ClubReset {
        let user = try currentUser()
        var reset = ClubReset()
        for event in try context.fetch(FetchDescriptor<ClubEvent>()) where !event.posterID.isEmpty && event.posterID == user.id {
            reset.deletedEvents.append(.init(eventID: event.id, clubID: event.clubID))
            context.delete(event)
        }
        reset.leftClubIDs = user.joinedClubIDs
        user.joinedClubIDs = []
        user.isVerifiedMember = false
        try context.save()
        return reset
    }

    private func club(id: String) throws -> Club? {
        try context.fetch(FetchDescriptor<Club>(predicate: #Predicate { $0.id == id })).first
    }

    private func currentUser() throws -> UserProfile { try context.currentUserProfile() }
}
