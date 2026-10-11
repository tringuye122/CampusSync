//
//  ClubsViewModel.swift
//  CampusSync
//
//  Drives the Clubs tab: upcoming club events (events are public), each checked against my class
//  schedule, filtered by All clubs / Free for me / Joined, and the Join / Pay Dues actions. Talks
//  only to repositories (through AppServices). Dues are a one-tap recorded flag; no real payment.
//

import Foundation
import Observation

enum ClubFilter: String, CaseIterable, Identifiable {
    case all = "All clubs"
    case freeForMe = "Free for me"
    case joined = "Joined"
    var id: String { rawValue }
}

@Observable
final class ClubsViewModel {
    /// One card: an upcoming event with its club's access and my availability for it.
    struct Item: Identifiable, Equatable {
        var id: String
        var clubID: String
        var clubName: String
        var access: ClubAccess
        var duesAmount: Int
        var eventTitle: String
        var location: String
        var start: Date
        var end: Date
        var availability: ClubAvailability
        var isJoined: Bool
        /// I posted this event, so I can remove it.
        var isMine = false
    }

    private(set) var items: [Item] = []
    /// Clubs I have joined: the ones an event can be posted for.
    private(set) var joinedClubs: [Club] = []
    var errorMessage: String?

    func load(services: AppServices, now: Date) async {
        do {
            let clubs = Dictionary(try await services.clubs.clubs().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let events = try await services.clubs.events(now: now)
            let user = try await services.users.currentUser()
            let joined = Set(user.joinedClubIDs)
            joinedClubs = clubs.values.filter { joined.contains($0.id) }.sorted { $0.name < $1.name }
            let slots = ((try? await services.schedule.classes()) ?? []).map(ClassSlot.init)

            items = events.map { event in
                let club = clubs[event.clubID]
                return Item(
                    id: event.id,
                    clubID: event.clubID,
                    clubName: club?.name ?? event.clubName,
                    access: club?.access ?? event.access,
                    duesAmount: club?.duesAmount ?? event.duesAmount,
                    eventTitle: event.title,
                    location: event.location,
                    start: event.startTime,
                    end: event.endTime,
                    availability: ClubAvailability.check(eventStart: event.startTime, eventEnd: event.endTime, classes: slots),
                    isJoined: joined.contains(event.clubID),
                    isMine: !event.posterID.isEmpty && event.posterID == user.id)
            }
            .sorted { $0.start < $1.start }
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load club events."
        }
    }

    func visibleItems(filter: ClubFilter) -> [Item] {
        switch filter {
        case .all: items
        case .freeForMe: items.filter { $0.availability.isFree }
        case .joined: items.filter(\.isJoined)
        }
    }

    // MARK: Actions

    /// Clubs with a membership change in flight. Their buttons are disabled, so a second tap cannot
    /// repeat the change or (on a card that has just flipped to "Joined") undo it.
    private(set) var busyClubIDs: Set<String> = []

    func isBusy(_ item: Item) -> Bool { busyClubIDs.contains(item.clubID) }

    /// Club events are real, public data. Demo mode keeps the student's schedule, friends and
    /// invites fictional, but must not create real events (and its pinned clock would make the
    /// rules reject them once real time passes it).
    static let demoPostMessage = "Club events are real. Turn off Demo mode to post one."

    private func changeMembership(
        _ item: Item, services: AppServices, now: Date, failure: String, _ change: () async throws -> Void
    ) async {
        guard busyClubIDs.insert(item.clubID).inserted else { return }
        defer { busyClubIDs.remove(item.clubID) }
        do {
            try await change()
            await services.syncWidget()   // refreshes the header's Verified Member pill
            await load(services: services, now: now)   // the card shows the new state before it is tappable again
        } catch {
            errorMessage = failure
        }
    }

    /// Leave a joined club. A dues club also loses its dues-paid state (and the Verified Member badge).
    func leave(_ item: Item, services: AppServices, now: Date) async {
        await changeMembership(item, services: services, now: now, failure: "Couldn't leave the club. Try again.") {
            try await services.clubs.leaveClub(id: item.clubID)
        }
    }

    /// Join for free clubs; Pay Dues (which also joins) for dues clubs.
    func act(on item: Item, services: AppServices, now: Date) async {
        await changeMembership(item, services: services, now: now, failure: "Couldn't update your membership. Try again.") {
            if item.access == .duesRequired {
                try await services.clubs.payDues(clubID: item.clubID)
            } else {
                try await services.clubs.joinClub(id: item.clubID)
            }
        }
    }

    /// Returns true when the event was posted.
    @discardableResult
    func post(_ draft: ClubEventDraft, services: AppServices, now: Date) async -> Bool {
        guard !services.isDemoMode else {
            errorMessage = Self.demoPostMessage
            return false
        }
        do {
            try await services.clubs.postEvent(draft)
            await load(services: services, now: now)
            await services.syncWidget()
            return true
        } catch {
            return false   // the sheet says so itself; `notMember` cannot happen from the club picker
        }
    }

    func delete(_ item: Item, services: AppServices, now: Date) async {
        do {
            try await services.clubs.deleteEvent(id: item.id)
            await load(services: services, now: now)
            await services.syncWidget()
        } catch {
            errorMessage = "Couldn't remove the event. Try again."
        }
    }
}
