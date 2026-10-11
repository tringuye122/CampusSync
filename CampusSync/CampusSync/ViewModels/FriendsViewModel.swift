//
//  FriendsViewModel.swift
//  CampusSync
//
//  Drives the Friends screen. Talks only to FriendRepository (through AppServices).
//  Every call fails soft: a failure sets a message and keeps the last good lists,
//  so the screen never blocks and still shows cached data when offline.
//

import Foundation
import Observation

@Observable
final class FriendsViewModel {
    private(set) var friends: [FriendSummary] = []
    private(set) var incoming: [FriendRequest] = []
    private(set) var outgoing: [FriendRequest] = []
    private(set) var isLoading = false
    /// True after a load failed, so the view can say it is showing saved data.
    private(set) var isOffline = false

    /// True while a request, answer or unfriend is being sent; the buttons are disabled meanwhile.
    private(set) var isWorking = false

    var searchText = ""
    private(set) var searchResults: [FriendSummary] = []
    /// True once a search for the current text has finished, so "no matches" is not shown while typing.
    private(set) var hasSearched = false
    var message: String?

    func load(services: AppServices) async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let friends = services.friends.friends()
            async let incoming = services.friends.incomingRequests()
            async let outgoing = services.friends.outgoingRequests()
            self.friends = try await friends
            self.incoming = try await incoming
            self.outgoing = try await outgoing
            isOffline = false
        } catch {
            isOffline = true
            message = Self.text(for: error)
        }
    }

    /// Searches as the student types. The view calls this from a task keyed on the text, which
    /// waits a moment first so each keystroke does not fire a query.
    func search(services: AppServices) async {
        let text = searchText
        guard AuthValidator.normalizeHandle(text).count >= FriendSearch.minimumLength else {
            searchResults = []
            hasSearched = false
            return
        }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }   // the text changed again; a newer search is coming
        do {
            let found = try await services.friends.searchHandles(prefix: text)
            guard !Task.isCancelled else { return }
            searchResults = found
            hasSearched = true
            message = nil
        } catch {
            guard !Task.isCancelled else { return }
            searchResults = []
            message = Self.text(for: error)
        }
    }

    /// What the search result's button should offer.
    func relationship(to student: FriendSummary) -> Relationship {
        if friends.contains(where: { $0.id == student.id }) { return .friend }
        if outgoing.contains(where: { $0.other.id == student.id }) { return .requested }
        if let request = incoming.first(where: { $0.other.id == student.id }) { return .wantsToBeFriends(request) }
        return .stranger
    }

    enum Relationship: Equatable {
        case friend, requested, stranger
        case wantsToBeFriends(FriendRequest)
    }

    func sendRequest(to student: FriendSummary, services: AppServices) async {
        await run(services) { try await services.friends.sendRequest(to: student) }
    }

    func accept(_ request: FriendRequest, services: AppServices) async {
        await run(services) { try await services.friends.accept(request) }
    }

    func decline(_ request: FriendRequest, services: AppServices) async {
        await run(services) { try await services.friends.decline(request) }
    }

    func cancel(_ request: FriendRequest, services: AppServices) async {
        await run(services) { try await services.friends.cancel(request) }
    }

    func unfriend(_ friend: FriendSummary, services: AppServices) async {
        await run(services) { try await services.friends.unfriend(friend) }
    }

    /// Runs a write, then reloads the lists, even after a failure: a failed answer usually means
    /// the lists were stale (for example the sender cancelled), and reloading fixes that.
    private func run(_ services: AppServices, _ action: () async throws -> Void) async {
        // One write at a time: a second tap while the first is in flight would send a duplicate
        // request or answer a request that is already answered.
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        message = nil
        var failure: String?
        do {
            try await action()
        } catch {
            failure = Self.text(for: error)
        }
        await load(services: services)
        if let failure { message = failure }
    }

    private static func text(for error: Error) -> String {
        (error as? FriendError)?.message ?? FriendError.unknown.message
    }
}
