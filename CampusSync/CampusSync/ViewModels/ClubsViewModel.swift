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
    }

    private(set) var items: [Item] = []
    var errorMessage: String?

    func load(services: AppServices, now: Date) async {
        do {
            let clubs = Dictionary(uniqueKeysWithValues: try await services.clubs.clubs().map { ($0.id, $0) })
            let events = try await services.clubs.events(now: now)
            let joined = Set(try await services.users.currentUser().joinedClubIDs)
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
                    isJoined: joined.contains(event.clubID))
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

    /// Join for free clubs; Pay Dues (which also joins) for dues clubs.
    func act(on item: Item, services: AppServices) async {
        do {
            if item.access == .duesRequired {
                try await services.clubs.payDues(clubID: item.clubID)
            } else {
                try await services.clubs.joinClub(id: item.clubID)
            }
            await services.syncWidget()   // refreshes the header's Verified Member pill
        } catch {
            errorMessage = "Couldn't update your membership. Try again."
        }
    }
}
