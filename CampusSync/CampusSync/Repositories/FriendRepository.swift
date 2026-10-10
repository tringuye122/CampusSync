//
//  FriendRepository.swift
//  CampusSync
//
//  Friend access: search by handle, request, accept, decline, unfriend. Like the
//  other repositories, views and view models only see this protocol. The Firestore
//  implementation is the real one; `InMemoryFriendRepository` serves previews and
//  tests. All methods are relative to the signed-in student and throw `FriendError`.
//

import Foundation

protocol FriendRepository {
    /// Students whose handle starts with `prefix` ("@" and case are ignored), at most
    /// `FriendSearch.maxResults`, never including me. Fewer than `FriendSearch.minimumLength`
    /// characters returns nothing, so a single letter cannot list everyone.
    func searchHandles(prefix: String) async throws -> [FriendSummary]
    func sendRequest(to student: FriendSummary) async throws
    /// Pending requests other students sent me.
    func incomingRequests() async throws -> [FriendRequest]
    /// Pending requests I sent.
    func outgoingRequests() async throws -> [FriendRequest]
    func accept(_ request: FriendRequest) async throws
    func decline(_ request: FriendRequest) async throws
    /// Withdraws a request I sent.
    func cancel(_ request: FriendRequest) async throws
    func friends() async throws -> [FriendSummary]
    /// Removes the friendship on both sides.
    func unfriend(_ friend: FriendSummary) async throws
}

/// A single-student simulation of the friend graph for previews and tests.
/// `directory` is everyone who can be found by handle.
final class InMemoryFriendRepository: FriendRepository {
    let me: FriendSummary
    var directory: [FriendSummary]
    private(set) var requests: [FriendRequest] = []
    private(set) var friendList: [FriendSummary] = []
    /// Set to simulate a failure such as `.offline`.
    var failure: FriendError?

    init(me: FriendSummary, directory: [FriendSummary] = [], friends: [FriendSummary] = []) {
        self.me = me
        self.directory = directory
        self.friendList = friends
    }

    /// Test helper: someone else asked to be my friend.
    func receiveRequest(from student: FriendSummary) {
        requests.append(FriendRequest(
            fromUID: student.id, toUID: me.id, status: .pending, createdAt: nil, other: student))
    }

    func searchHandles(prefix: String) async throws -> [FriendSummary] {
        try check()
        let normalized = AuthValidator.normalizeHandle(prefix)
        guard normalized.count >= FriendSearch.minimumLength else { return [] }
        guard FriendSearch.isValidPrefix(normalized) else { throw FriendError.invalidHandle }
        return Array(directory
            .filter { $0.handle.hasPrefix(normalized) && $0.id != me.id }
            .sorted { $0.handle < $1.handle }
            .prefix(FriendSearch.maxResults))
    }

    func sendRequest(to student: FriendSummary) async throws {
        try check()
        guard student.id != me.id else { throw FriendError.cannotAddSelf }
        guard !friendList.contains(where: { $0.id == student.id }) else { throw FriendError.alreadyFriends }
        guard !requests.contains(where: { $0.status == .pending && $0.other.id == student.id }) else {
            throw FriendError.requestPending
        }
        requests.append(FriendRequest(
            fromUID: me.id, toUID: student.id, status: .pending, createdAt: nil, other: student))
    }

    func incomingRequests() async throws -> [FriendRequest] {
        try check()
        return requests.filter { $0.status == .pending && $0.toUID == me.id }
    }

    func outgoingRequests() async throws -> [FriendRequest] {
        try check()
        return requests.filter { $0.status == .pending && $0.fromUID == me.id }
    }

    func accept(_ request: FriendRequest) async throws {
        try check()
        // Like Firestore: answering a request that is already gone (cancelled) fails.
        guard requests.contains(where: { $0.id == request.id }) else { throw FriendError.requestGone }
        requests.removeAll { $0.id == request.id }
        if !friendList.contains(where: { $0.id == request.other.id }) {
            friendList.append(request.other)
        }
    }

    func decline(_ request: FriendRequest) async throws {
        try check()
        guard requests.contains(where: { $0.id == request.id }) else { throw FriendError.requestGone }
        requests.removeAll { $0.id == request.id }
    }

    func cancel(_ request: FriendRequest) async throws {
        try check()
        requests.removeAll { $0.id == request.id }
    }

    func friends() async throws -> [FriendSummary] {
        try check()
        return friendList.sorted { $0.displayName < $1.displayName }
    }

    func unfriend(_ friend: FriendSummary) async throws {
        try check()
        friendList.removeAll { $0.id == friend.id }
    }

    private func check() throws {
        if let failure { throw failure }
    }
}

extension InMemoryFriendRepository {
    /// Fictional students for previews, matching the seed friends.
    static func preview() -> InMemoryFriendRepository {
        let me = FriendSummary(id: SampleData.userID, displayName: "Tri Nguyen", handle: "tri")
        let maya = FriendSummary(id: SampleData.mayaID, displayName: "Maya Patel", handle: "maya")
        let jordan = FriendSummary(id: SampleData.jordanID, displayName: "Jordan Lee", handle: "jordan")
        let sam = FriendSummary(id: SampleData.samID, displayName: "Sam Rivera", handle: "sam")
        let repo = InMemoryFriendRepository(
            me: me,
            directory: [maya, jordan, sam, FriendSummary(id: "seed-user-riley", displayName: "Riley Chen", handle: "riley")],
            friends: [maya, jordan])
        repo.receiveRequest(from: sam)
        return repo
    }
}
