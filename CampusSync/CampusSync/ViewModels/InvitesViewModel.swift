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
    /// The student's id and name, copied out so no live model is kept (see DetachedCopies.swift).
    private(set) var userID: String?
    private(set) var userName: String?
    var errorMessage: String?

    func load(services: AppServices, now: Date) async {
        do {
            let user = try await services.users.currentUser()
            userID = user.id
            userName = user.displayName
            friends = try await services.schedule.friends().map(\.detachedCopy)
            invites = try await services.invites.activeInvites(now: now).map(\.detachedCopy)
        } catch {
            errorMessage = "Couldn't load invites."
        }
    }

    /// Unexpired invites matching the chip, soonest first (the Invites tab shows one flat list).
    func filteredInvites(at now: Date, filter: InviteFilter) -> [OpenInvite] {
        invites
            .filter { !$0.isExpired(at: now) && filter.includes($0) }
            .sorted { $0.startTime < $1.startTime }
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

    /// Invites with an RSVP change in flight. RSVP is a toggle, so a second tap before the first
    /// finishes would undo it.
    private(set) var busyInviteIDs: Set<String> = []

    func isBusy(_ invite: OpenInvite) -> Bool { busyInviteIDs.contains(invite.id) }

    func toggleRSVP(_ invite: OpenInvite, services: AppServices, now: Date) async {
        guard busyInviteIDs.insert(invite.id).inserted else { return }
        defer { busyInviteIDs.remove(invite.id) }
        do {
            try await services.invites.toggleRSVP(inviteID: invite.id)
            await services.syncWidget()
            // Reload before the button is tappable again, so it never shows the old state.
            await load(services: services, now: now)
        } catch RepositoryError.inviteFull {
            errorMessage = "That plan is full."
        } catch {
            errorMessage = "Couldn't update your RSVP."
        }
    }

    /// Returns true when the invite was saved.
    @discardableResult
    func post(_ draft: ComposeDraft, services: AppServices, now: Date) async -> Bool {
        guard let userID, let userName else { return false }
        do {
            try await services.invites.post(draft.makeInvite(hostID: userID, hostName: userName))
            await load(services: services, now: now)
            await services.syncWidget()
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
