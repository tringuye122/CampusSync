//
//  HomeViewModel.swift
//  CampusSync
//
//  Drives the Home tab: the FREE NOW hero and Today card (class meetings), the
//  "Friends free now" cards (my meetings against each friend's shared meetings), and the
//  active invites carousel.
//

import Foundation
import Observation

@Observable
final class HomeViewModel {
    private(set) var meetings: [SnapshotMeeting] = []
    private(set) var myClassMeetings: [ClassMeeting] = []
    private(set) var friends: [FriendSchedule] = []
    private(set) var invites: [OpenInvite] = []
    private(set) var userID: String?

    func load(services: AppServices, now: Date) async {
        let classes = (try? await services.schedule.classes()) ?? []
        meetings = classes.flatMap(\.snapshotMeetings)
        myClassMeetings = classes.map(\.meeting)
        friends = ((try? await services.schedule.friends()) ?? []).map {
            FriendSchedule(id: $0.id, name: $0.displayName, meetings: $0.classes)
        }
        userID = try? await services.users.currentUser().id
        invites = (try? await services.invites.activeInvites(now: now)) ?? []
    }

    /// Today's classes in order, for the collapsible Today card. Empty on weekends.
    func todayMeetings(at now: Date, calendar: Calendar = .current) -> [SnapshotMeeting] {
        let weekday = calendar.component(.weekday, from: now)
        return meetings.filter { $0.weekday == weekday }.sorted { $0.startMinutes < $1.startMinutes }
    }

    /// The next class that starts later today, if any.
    func nextClassToday(at now: Date, calendar: Calendar = .current) -> SnapshotMeeting? {
        let minute = now.minutesSinceMidnight(in: calendar)
        return todayMeetings(at: now, calendar: calendar).first { $0.startMinutes > minute }
    }

    /// Every friend and where they stand right now.
    func friendStatuses(at now: Date, calendar: Calendar = .current) -> [FriendStatus] {
        FriendsFreeNow.statuses(mine: myClassMeetings, friends: friends, now: now, calendar: calendar)
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
