//
//  DemoRepositories.swift
//  CampusSync
//
//  The two demo-mode repositories that need more than the local ones: the user (club membership
//  stays live) and friends (accepting or removing a friend must change the demo schedule data too).
//

import Foundation
import SwiftData

/// The demo user, with Verified Member and joined clubs taken from the live profile, because
/// Join and Pay Dues stay live. Everything else about the demo user is demo data.
@MainActor
final class DemoUserRepository: UserRepository {
    private let demo: UserRepository
    private let live: UserRepository

    init(demo: UserRepository, live: UserRepository) {
        self.demo = demo
        self.live = live
    }

    func currentUser() async throws -> UserProfile {
        let user = try await demo.currentUser()
        if let real = try? await live.currentUser() {
            user.joinedClubIDs = real.joinedClubIDs
            user.isVerifiedMember = real.isVerifiedMember
        }
        return user
    }
}

/// Friends for demo mode: an in-memory friend graph that also adds or removes the friend's shared
/// schedule in the demo database, so accepting Sam makes Sam appear on Home and Schedule.
@MainActor
final class DemoFriendRepository: FriendRepository {
    private let inner: InMemoryFriendRepository
    private let context: ModelContext
    private let userID: String

    init(inner: InMemoryFriendRepository, context: ModelContext, userID: String) {
        self.inner = inner
        self.context = context
        self.userID = userID
    }

    func searchHandles(prefix: String) async throws -> [FriendSummary] { try await inner.searchHandles(prefix: prefix) }
    func sendRequest(to student: FriendSummary) async throws { try await inner.sendRequest(to: student) }
    func incomingRequests() async throws -> [FriendRequest] { try await inner.incomingRequests() }
    func outgoingRequests() async throws -> [FriendRequest] { try await inner.outgoingRequests() }
    func decline(_ request: FriendRequest) async throws { try await inner.decline(request) }
    func cancel(_ request: FriendRequest) async throws { try await inner.cancel(request) }
    func friends() async throws -> [FriendSummary] { try await inner.friends() }

    func accept(_ request: FriendRequest) async throws {
        try await inner.accept(request)
        let person = DemoCast.directory.first { $0.id == request.other.id }
        setFriendship(with: request.other.id, name: request.other.displayName, meetings: person?.meetings ?? [], isFriend: true)
    }

    func unfriend(_ friend: FriendSummary) async throws {
        try await inner.unfriend(friend)
        setFriendship(with: friend.id, name: friend.displayName, meetings: [], isFriend: false)
    }

    private func setFriendship(with id: String, name: String, meetings: [ClassMeeting], isFriend: Bool) {
        let profiles = (try? context.fetch(FetchDescriptor<FriendProfile>())) ?? []
        let existing = profiles.first { $0.id == id }
        if isFriend {
            if existing == nil { context.insert(FriendProfile(id: id, displayName: name, classes: meetings)) }
        } else if let existing {
            context.delete(existing)
        }
        if let user = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first {
            user.friendIDs.removeAll { $0 == id }
            if isFriend { user.friendIDs.append(id) }
        }
        try? context.save()
    }
}
