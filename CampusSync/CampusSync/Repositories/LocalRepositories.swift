//
//  LocalRepositories.swift
//  CampusSync
//
//  SwiftData-backed implementations of the repository protocols, seeded from
//  SampleData. Fully offline. The Firestore versions will implement the same
//  protocols later.
//

import Foundation
import SwiftData

/// Seeds and resets the local store.
@MainActor
struct LocalDataStore {
    let context: ModelContext

    /// Inserts seed data only when the store is empty.
    func seedIfNeeded(now: Date) throws {
        guard try context.fetchCount(FetchDescriptor<UserProfile>()) == 0 else { return }
        try insertSeed(now: now)
    }

    /// Wipes everything and reseeds. Invite and event times are regenerated relative to `now`.
    func resetToSeed(now: Date) throws {
        try context.delete(model: UserProfile.self)
        try context.delete(model: ClassSchedule.self)
        try context.delete(model: FriendProfile.self)
        try context.delete(model: OpenInvite.self)
        try context.delete(model: Club.self)
        try context.delete(model: ClubEvent.self)
        try insertSeed(now: now)
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

    func currentUser() async throws -> UserProfile {
        guard let user = try context.fetch(FetchDescriptor<UserProfile>()).first else {
            throw RepositoryError.notSeeded
        }
        return user
    }
}

@MainActor
final class LocalScheduleRepository: ScheduleRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
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

    func professorInfo(for instructor: String) async -> ProfessorInfo? {
        SampleData.professors[instructor]
    }

    private func currentUser() throws -> UserProfile {
        guard let user = try context.fetch(FetchDescriptor<UserProfile>()).first else {
            throw RepositoryError.notSeeded
        }
        return user
    }
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

    func toggleRSVP(inviteID: UUID) async throws {
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

    private func currentUser() throws -> UserProfile {
        guard let user = try context.fetch(FetchDescriptor<UserProfile>()).first else {
            throw RepositoryError.notSeeded
        }
        return user
    }
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

    func joinClub(id: UUID) async throws {
        let user = try currentUser()
        guard try club(id: id) != nil else { throw RepositoryError.notFound }
        if !user.joinedClubIDs.contains(id) {
            user.joinedClubIDs.append(id)
        }
        try context.save()
    }

    func payDues(clubID: UUID) async throws {
        let user = try currentUser()
        guard let club = try club(id: clubID) else { throw RepositoryError.notFound }
        guard club.access == .duesRequired else { throw RepositoryError.notDuesClub }
        if !user.joinedClubIDs.contains(clubID) {
            user.joinedClubIDs.append(clubID)
        }
        user.isVerifiedMember = true
        try context.save()
    }

    private func club(id: UUID) throws -> Club? {
        try context.fetch(FetchDescriptor<Club>(predicate: #Predicate { $0.id == id })).first
    }

    private func currentUser() throws -> UserProfile {
        guard let user = try context.fetch(FetchDescriptor<UserProfile>()).first else {
            throw RepositoryError.notSeeded
        }
        return user
    }
}
