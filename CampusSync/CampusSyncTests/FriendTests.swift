//
//  FriendTests.swift
//  CampusSyncTests
//
//  Friend graph behavior against the in-memory repository, plus the view model that
//  sits on top of it. The Firestore implementation is covered by the rules tests
//  (firebase/test/rules.test.js) and the emulator integration run.
//

import Foundation
import Testing
@testable import CampusSync

@MainActor
struct FriendTests {
    private let me = FriendSummary(id: "uid-me", displayName: "Me Student", handle: "me")
    private let ann = FriendSummary(id: "uid-ann", displayName: "Ann Lee", handle: "ann_lee")
    private let bob = FriendSummary(id: "uid-bob", displayName: "Bob Ray", handle: "bob")

    private func repo(friends: [FriendSummary] = []) -> InMemoryFriendRepository {
        InMemoryFriendRepository(me: me, directory: [ann, bob], friends: friends)
    }

    @Test func searchMatchesHandlePrefixesIgnoringAtSignAndCase() async throws {
        let repository = InMemoryFriendRepository(
            me: me, directory: [ann, bob, FriendSummary(id: "uid-anna", displayName: "Anna K", handle: "anna")])
        #expect(try await repository.searchHandles(prefix: "  @AN ").map(\.handle) == ["ann_lee", "anna"])
        #expect(try await repository.searchHandles(prefix: "ann_l").map(\.id) == [ann.id])
        #expect(try await repository.searchHandles(prefix: "zz").isEmpty)
    }

    @Test func searchNeedsTwoCharactersAndNeverReturnsMeOrMoreThanTen() async throws {
        let many = (0..<15).map { FriendSummary(id: "u\($0)", displayName: "N\($0)", handle: "pal\($0)") }
        let repository = InMemoryFriendRepository(
            me: FriendSummary(id: "uid-me", displayName: "Me", handle: "pal_me"), directory: many + [
                FriendSummary(id: "uid-me", displayName: "Me", handle: "pal_me")])
        #expect(try await repository.searchHandles(prefix: "p").isEmpty)           // one letter lists nobody
        let found = try await repository.searchHandles(prefix: "pal")
        #expect(found.count == FriendSearch.maxResults)
        #expect(!found.contains { $0.id == "uid-me" })
        await #expect(throws: FriendError.invalidHandle) { try await repository.searchHandles(prefix: "a!") }
    }

    @Test func requestsCannotTargetYourselfFriendsOrRepeat() async throws {
        let repository = repo(friends: [bob])
        await #expect(throws: FriendError.cannotAddSelf) { try await repository.sendRequest(to: me) }
        await #expect(throws: FriendError.alreadyFriends) { try await repository.sendRequest(to: bob) }
        try await repository.sendRequest(to: ann)
        await #expect(throws: FriendError.requestPending) { try await repository.sendRequest(to: ann) }
        #expect(try await repository.outgoingRequests().map(\.other) == [ann])
    }

    @Test func acceptingAnIncomingRequestMakesFriends() async throws {
        let repository = repo()
        repository.receiveRequest(from: ann)
        let request = try #require(try await repository.incomingRequests().first)
        try await repository.accept(request)
        #expect(try await repository.friends() == [ann])
        #expect(try await repository.incomingRequests().isEmpty)
    }

    @Test func decliningAndUnfriendingRemoveThem() async throws {
        let repository = repo(friends: [bob])
        repository.receiveRequest(from: ann)
        try await repository.decline(try #require(try await repository.incomingRequests().first))
        #expect(try await repository.incomingRequests().isEmpty)
        try await repository.unfriend(bob)
        #expect(try await repository.friends().isEmpty)
    }

    @Test func requestIDMatchesTheFirestoreDocumentID() {
        #expect(FriendRequest.makeID(from: "a", to: "b") == "a_b")
    }

    @Test func viewModelReportsRelationshipsAndFailsSoft() async throws {
        let repository = repo(friends: [bob])
        repository.receiveRequest(from: ann)
        let services = AppServices.preview(friends: repository)
        let viewModel = FriendsViewModel()
        await viewModel.load(services: services)
        #expect(viewModel.friends == [bob])
        #expect(viewModel.relationship(to: bob) == .friend)
        #expect(viewModel.relationship(to: ann) == .wantsToBeFriends(viewModel.incoming[0]))

        repository.failure = .offline
        await viewModel.load(services: services)
        #expect(viewModel.isOffline)
        #expect(viewModel.friends == [bob])   // last good data is kept
        #expect(viewModel.message == FriendError.offline.message)
    }

    @Test func seedIDsAreStableStrings() {
        #expect(SampleData.userID == "seed-user-demo")
        #expect(Set(SampleData.user().friendIDs) == [SampleData.mayaID, SampleData.jordanID, SampleData.samID])
    }
}

@MainActor
struct FriendSearchViewModelTests {
    @Test func typingShowsMatchesAndShortTextClearsThem() async {
        let services = AppServices.preview()   // directory: maya, jordan, sam, riley
        let viewModel = FriendsViewModel()
        viewModel.searchText = "ma"
        await viewModel.search(services: services)
        #expect(viewModel.searchResults.map(\.handle) == ["maya"])
        #expect(viewModel.hasSearched)

        viewModel.searchText = "zz"
        await viewModel.search(services: services)
        #expect(viewModel.searchResults.isEmpty && viewModel.hasSearched)   // "no matches" state

        viewModel.searchText = "m"
        await viewModel.search(services: services)
        #expect(viewModel.searchResults.isEmpty && !viewModel.hasSearched)  // too short: nothing, no message
    }

    @Test func aFailedAnswerStillReloadsTheStaleLists() async {
        let repository = InMemoryFriendRepository.preview()
        let services = AppServices.preview(friends: repository)
        let viewModel = FriendsViewModel()
        await viewModel.load(services: services)
        let stale = viewModel.incoming[0]
        // The sender cancels while this screen still shows the request.
        try? await repository.decline(stale)
        await viewModel.accept(stale, services: services)
        #expect(viewModel.message == FriendError.requestGone.message)   // says what happened, not "permission"
        #expect(viewModel.incoming.isEmpty)                             // and the stale list was refreshed
        #expect(!viewModel.message!.localizedCaseInsensitiveContains("email"))
    }
}
