//
//  AppRouter.swift
//  CampusSync
//
//  Owns the selected tab so a widget tap can jump to the right one.
//  Deep links look like campussync://schedule or campussync://invites.
//

import Foundation
import Observation

/// The three segments at the top of the Schedule tab.
enum ScheduleSegment: String, CaseIterable, Identifiable {
    case timetable = "Timetable"
    case friends = "Friends"
    case classes = "Classes"
    var id: String { rawValue }
}

@Observable
final class AppRouter {
    var selectedTab: AppTab = .home
    var scheduleSegment: ScheduleSegment = .timetable
    /// Set when a Home card opens the Friends segment on a particular friend.
    var focusedFriendID: String?

    /// Jumps to Schedule > Friends with `friendID` selected.
    func showFriendOverlap(friendID: String) {
        focusedFriendID = friendID
        scheduleSegment = .friends
        selectedTab = .schedule
    }

    static let scheme = "campussync"

    func open(_ url: URL) {
        guard url.scheme == Self.scheme,
              let host = url.host,
              let tab = AppTab(rawValue: host)
        else { return }
        selectedTab = tab
    }
}
