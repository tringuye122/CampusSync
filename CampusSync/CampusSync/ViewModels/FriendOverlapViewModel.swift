//
//  FriendOverlapViewModel.swift
//  CampusSync
//
//  Drives the Friend Overlap view: one friend at a time, their mutual free windows with me,
//  and turning a window into a prefilled invite. Talks only to repositories (through
//  AppServices) and the pure OverlapEngine.
//

import Foundation
import Observation

@Observable
final class FriendOverlapViewModel {
    /// What the screen should show, in priority order.
    enum State: Equatable {
        case noFriends
        case noOwnSchedule
        case friendHasNoSchedule(name: String)
        /// A friend with a shared schedule is selected: show the two-column timeline.
        case ready(friendName: String)
    }

    private(set) var friends: [FriendProfile] = []
    private(set) var myMeetings: [ClassMeeting] = []
    private(set) var windows: [OverlapWindow] = []
    var selectedFriendID: String? {
        didSet { recompute() }
    }
    var selectedDay: Weekday = .mon
    /// Set to present the compose sheet.
    var composeDraft: ComposeDraft?
    var errorMessage: String?
    /// Set after a successful post, so the view can confirm it.
    private(set) var postedToName: String?

    let settings: FreeSlotSettings

    init(settings: FreeSlotSettings = .standard) {
        self.settings = settings
    }

    var selectedFriend: FriendProfile? {
        friends.first { $0.id == selectedFriendID }
    }

    var state: State {
        guard !friends.isEmpty else { return .noFriends }
        guard !myMeetings.isEmpty else { return .noOwnSchedule }
        guard let friend = selectedFriend else { return .noFriends }
        // A friend with no shared meetings is not "free all day": they have not imported a
        // schedule, or turned sharing off. Say so instead of listing every hour.
        guard !friend.classes.isEmpty else { return .friendHasNoSchedule(name: friend.displayName) }
        return .ready(friendName: friend.displayName)
    }

    /// Mutual free windows on one day, in time order, for the timeline.
    func windows(on day: Weekday) -> [OverlapWindow] {
        windows.filter { $0.weekday == day }.sorted { $0.startMinutes < $1.startMinutes }
    }

    /// The longest mutual window on `day` with `friend` (shown under their avatar), or nil.
    func longestWindow(with friend: FriendProfile, on day: Weekday) -> OverlapWindow? {
        guard !myMeetings.isEmpty, !friend.classes.isEmpty else { return nil }
        return OverlapEngine.mutualFreeWindows(mine: myMeetings, theirs: friend.classes, settings: settings)
            .filter { $0.weekday == day }
            .max { $0.durationMinutes < $1.durationMinutes }
    }

    /// Class meetings of the selected friend on `day`, as the timeline draws them ("Class" blocks).
    func friendMeetings(on day: Weekday) -> [ClassMeeting] {
        (selectedFriend?.classes ?? []).filter { $0.weekdays.contains(day) }.sorted { $0.startMinutes < $1.startMinutes }
    }

    func myMeetings(on day: Weekday) -> [ClassMeeting] {
        myMeetings.filter { $0.weekdays.contains(day) }.sorted { $0.startMinutes < $1.startMinutes }
    }

    /// `focus` is a friend chosen from a Home card; it wins over the current selection once.
    func load(services: AppServices, focus: String? = nil) async {
        do {
            myMeetings = try await services.schedule.classes().map(\.meeting)
            friends = try await services.schedule.friends()
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load schedules."
        }
        // Keep the selection if that friend is still there; otherwise pick the first.
        if let focus, friends.contains(where: { $0.id == focus }) {
            selectedFriendID = focus
        } else if selectedFriend == nil {
            selectedFriendID = friends.first?.id
        }
        recompute()
    }

    private func recompute() {
        guard let friend = selectedFriend, !myMeetings.isEmpty, !friend.classes.isEmpty else {
            windows = []
            return
        }
        windows = OverlapEngine.mutualFreeWindows(mine: myMeetings, theirs: friend.classes, settings: settings)
    }

    /// Opens the compose sheet for a window: the next time it happens, 60 minutes (or what fits),
    /// with only the selected friend invited.
    func startInvite(for window: OverlapWindow, now: Date) {
        guard let friend = selectedFriend else { return }
        guard let draft = ComposeDraft.forSlot(window, friendID: friend.id, now: now) else {
            errorMessage = "That time has already passed this week. Try another window."
            return
        }
        composeDraft = draft
    }

    /// Returns true when the invite was saved.
    @discardableResult
    func post(_ draft: ComposeDraft, services: AppServices) async -> Bool {
        do {
            let user = try await services.users.currentUser()
            try await services.invites.post(draft.makeInvite(hostID: user.id, hostName: user.displayName))
            await services.syncWidget()
            postedToName = selectedFriend?.displayName
            return true
        } catch {
            errorMessage = "Couldn't post your invite."
            return false
        }
    }

    func clearPostedConfirmation() {
        postedToName = nil
    }
}
