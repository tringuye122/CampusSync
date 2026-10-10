//
//  FriendsFreeNow.swift
//  CampusSync
//
//  Where each friend stands right now, for the Home "Friends free now" cards: free with me
//  (mutual window), free, in class, or not sharing a schedule. Pure functions; `now` always
//  comes from AppClock.
//

import Foundation

/// A friend's shared meetings, decoupled from the SwiftData model.
struct FriendSchedule: Equatable, Identifiable {
    var id: String
    var name: String
    var meetings: [ClassMeeting]
}

struct FriendFreeNow: Identifiable, Equatable {
    var id: String { friendID }
    var friendID: String
    var name: String
    /// The mutual free window that contains "now".
    var window: OverlapWindow
    /// Bars for the rest of today, starting at now.
    var strip: DayStrip

    /// Minutes left in the shared window from `now`.
    func remainingMinutes(at now: Int) -> Int { window.endMinutes - now }
}

enum FriendsFreeNow {
    /// How far ahead the bars look (the design's axis runs from Now to about 6 hours later).
    static let lookaheadMinutes = 6 * 60

    /// Friends who share a free window with me that includes now, longest remaining first.
    /// A friend with no shared meetings is skipped (not "free all day": no schedule shared).
    static func compute(
        mine: [ClassMeeting],
        friends: [FriendSchedule],
        now: Date,
        calendar: Calendar = .current,
        settings: FreeSlotSettings = .standard
    ) -> [FriendFreeNow] {
        guard let weekday = Weekday(rawValue: calendar.component(.weekday, from: now)) else { return [] }   // weekend
        let nowMinutes = now.minutesSinceMidnight(in: calendar)
        let rangeEnd = min(settings.dayEndMinutes, nowMinutes + lookaheadMinutes)
        guard rangeEnd > nowMinutes else { return [] }

        var result: [FriendFreeNow] = []
        for friend in friends where !friend.meetings.isEmpty {
            let windows = OverlapEngine.mutualFreeWindows(mine: mine, theirs: friend.meetings, settings: settings)
            guard let current = windows.first(where: {
                $0.weekday == weekday && $0.startMinutes <= nowMinutes && nowMinutes < $0.endMinutes
            }) else { continue }
            result.append(FriendFreeNow(
                friendID: friend.id,
                name: friend.name,
                window: current,
                strip: DayStrip.make(
                    mine: mine, theirs: friend.meetings, on: weekday,
                    from: nowMinutes, to: rangeEnd, settings: settings)))
        }
        return result.sorted {
            ($1.remainingMinutes(at: nowMinutes), $0.name) < ($0.remainingMinutes(at: nowMinutes), $1.name)
        }
    }
}

/// One friend's status at a moment, for a card on Home.
struct FriendStatus: Identifiable, Equatable {
    enum State: Equatable {
        /// Free now and so am I; `until` is when the shared window ends.
        case mutualFree(until: Int)
        /// Free now but I am not; `minutes` is how long until their next class today (nil: rest of today).
        case free(minutes: Int?)
        /// In class now; `until` is when the class (and any class right after it) ends.
        case inClass(until: Int)
        /// No shared meetings to judge from.
        case notShared
    }

    var id: String { friendID }
    var friendID: String
    var name: String
    var state: State

    /// Lower sorts first: mutual, then free, then in class, then not shared.
    fileprivate var rank: Int {
        switch state {
        case .mutualFree: 0
        case .free: 1
        case .inClass: 2
        case .notShared: 3
        }
    }
}

extension FriendsFreeNow {
    /// Every friend with their status, mutual windows (longest remaining first) at the front.
    /// On weekends nobody has class, so friends who share a schedule are simply free.
    static func statuses(
        mine: [ClassMeeting],
        friends: [FriendSchedule],
        now: Date,
        calendar: Calendar = .current,
        settings: FreeSlotSettings = .standard
    ) -> [FriendStatus] {
        let nowMinutes = now.minutesSinceMidnight(in: calendar)
        let weekday = Weekday(rawValue: calendar.component(.weekday, from: now))
        let mutual = Dictionary(
            uniqueKeysWithValues: compute(mine: mine, friends: friends, now: now, calendar: calendar, settings: settings)
                .map { ($0.friendID, $0.window.endMinutes) })

        func state(of friend: FriendSchedule) -> FriendStatus.State {
            guard !friend.meetings.isEmpty else { return .notShared }
            if let end = mutual[friend.id] { return .mutualFree(until: end) }
            guard let weekday else { return .free(minutes: nil) }
            let today = friend.meetings.filter { $0.weekdays.contains(weekday) }.sorted { $0.startMinutes < $1.startMinutes }
            if let current = today.first(where: { $0.startMinutes <= nowMinutes && nowMinutes < $0.endMinutes }) {
                // Back-to-back classes count as one stretch of "in class".
                var end = current.endMinutes
                while let next = today.first(where: { $0.startMinutes <= end && $0.endMinutes > end }) { end = next.endMinutes }
                return .inClass(until: end)
            }
            return .free(minutes: today.first { $0.startMinutes > nowMinutes }.map { $0.startMinutes - nowMinutes })
        }

        return friends
            .map { FriendStatus(friendID: $0.id, name: $0.name, state: state(of: $0)) }
            .sorted { lhs, rhs in
                if lhs.rank != rhs.rank { return lhs.rank < rhs.rank }
                if case .mutualFree(let a) = lhs.state, case .mutualFree(let b) = rhs.state, a != b { return a > b }
                return lhs.name < rhs.name
            }
    }
}
