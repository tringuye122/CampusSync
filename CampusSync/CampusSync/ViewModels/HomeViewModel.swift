//
//  HomeViewModel.swift
//  CampusSync
//
//  Drives the Home tab: class meetings for the Live Status banner and active
//  invites for the carousel.
//

import Foundation
import Observation

@Observable
final class HomeViewModel {
    private(set) var meetings: [SnapshotMeeting] = []
    private(set) var invites: [OpenInvite] = []
    private(set) var userID: UUID?

    func load(services: AppServices, now: Date) async {
        meetings = ((try? await services.schedule.classes()) ?? []).flatMap(\.snapshotMeetings)
        userID = try? await services.users.currentUser().id
        invites = (try? await services.invites.activeInvites(now: now)) ?? []
    }

    /// Unexpired invites, soonest first.
    func activeInvites(at now: Date) -> [OpenInvite] {
        invites
            .filter { !$0.isExpired(at: now) }
            .sorted { $0.startTime < $1.startTime }
    }

    func isGoing(_ invite: OpenInvite) -> Bool {
        guard let userID else { return false }
        return invite.attendeeIDs.contains(userID)
    }

    func isFull(_ invite: OpenInvite) -> Bool {
        invite.attendeeIDs.count >= invite.capacity && !isGoing(invite)
    }

    func toggleRSVP(_ invite: OpenInvite, services: AppServices) async {
        try? await services.invites.toggleRSVP(inviteID: invite.id)
        await services.syncWidget()
    }
}
