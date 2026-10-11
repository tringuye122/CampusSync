//
//  FriendRowTests.swift
//  CampusSyncTests
//
//  The Schedule > Friends row: the + tile's pending-request badge and unfriending from the row.
//

import Foundation
import Testing
@testable import CampusSync

@MainActor
struct FriendRowTests {
    private func make() -> (FriendOverlapViewModel, AppServices, InMemoryFriendRepository) {
        let repo = InMemoryFriendRepository.preview()
        return (FriendOverlapViewModel(), AppServices.preview(friends: repo), repo)
    }

    @Test func theBadgeCountsWaitingRequests() async {
        let (model, services, _) = make()
        await model.load(services: services)
        #expect(model.pendingRequestCount == 1)   // Sam asked to be friends
    }

    @Test func offlineKeepsTheLastBadgeCount() async {
        let (model, services, repo) = make()
        await model.load(services: services)
        repo.failure = .offline
        await model.load(services: services)
        #expect(model.pendingRequestCount == 1)
    }

    @Test func unfriendingRemovesThemFromTheRowAndTheRepositoryAndMovesTheSelection() async throws {
        let (model, services, repo) = make()
        await model.load(services: services)
        let target = try #require(model.friends.first)
        model.selectedFriendID = target.id

        await model.unfriend(target, services: services)

        #expect(!model.friends.contains { $0.id == target.id })
        #expect(!repo.friendList.contains { $0.id == target.id })
        #expect(model.selectedFriendID != target.id)
        #expect(model.errorMessage == nil)
    }

    @Test func aFailedUnfriendKeepsTheFriendAndSaysSo() async throws {
        let (model, services, repo) = make()
        await model.load(services: services)
        let target = try #require(model.friends.first)
        repo.failure = .offline

        await model.unfriend(target, services: services)

        #expect(model.friends.contains { $0.id == target.id })
        #expect(model.errorMessage?.contains(target.displayName) == true)
    }
}
