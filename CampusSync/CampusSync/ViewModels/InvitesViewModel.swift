//
//  InvitesViewModel.swift
//  CampusSync
//
//  Drives the Invites tab. Talks only to repositories (through AppServices).
//  Expiry is applied at read time via InviteTiming; `load` just refreshes the
//  raw list, and views re-filter against the clock every minute.
//

import Foundation
import Observation

@Observable
final class InvitesViewModel {
    private(set) var invites: [OpenInvite] = []
    private(set) var friends: [FriendProfile] = []
    private(set) var user: UserProfile?
    var errorMessage: String?

    var userID: UUID? { user?.id }

    func load(services: AppServices, now: Date) async {
        do {
            user = try await services.users.currentUser()
            friends = try await services.schedule.friends()
            invites = try await services.invites.activeInvites(now: now)
        } catch {
            errorMessage = "Couldn't load invites."
        }
    }

    func sections(at now: Date) -> [InviteSection] {
        InviteTiming.sections(for: invites, now: now)
    }

    func isGoing(_ invite: OpenInvite) -> Bool {
        guard let userID else { return false }
        return invite.attendeeIDs.contains(userID)
    }

    func isFull(_ invite: OpenInvite) -> Bool {
        invite.attendeeIDs.count >= invite.capacity && !isGoing(invite)
    }

    func toggleRSVP(_ invite: OpenInvite, services: AppServices) async {
        do {
            try await services.invites.toggleRSVP(inviteID: invite.id)
        } catch RepositoryError.inviteFull {
            errorMessage = "That plan is full."
        } catch {
            errorMessage = "Couldn't update your RSVP."
        }
    }

    /// Returns true when the invite was saved.
    @discardableResult
    func post(_ draft: ComposeDraft, services: AppServices, now: Date) async -> Bool {
        guard let user else { return false }
        do {
            try await services.invites.post(draft.makeInvite(hostID: user.id, hostName: user.displayName))
            await load(services: services, now: now)
            return true
        } catch {
            errorMessage = "Couldn't post your invite."
            return false
        }
    }

    func standardDraft(now: Date) -> ComposeDraft {
        ComposeDraft.standard(now: now, friendIDs: friends.map(\.id))
    }
}
