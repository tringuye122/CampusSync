//
//  WidgetFriendStatus.swift
//  CampusSync
//
//  Who is free and who is in class, for the widget's medium and large sizes. Works on the
//  plain snapshot types so the app and the widget share one code path (no model types), and
//  takes `now` as input. There are only two states here, free or in class: the widget does not
//  compare a friend's schedule with mine. Must be a member of both the app and widget targets.
//

import Foundation

nonisolated struct WidgetFriendRow: Identifiable, Equatable {
    enum State: Equatable {
        /// Free now; `until` is when their next class today starts (nil: no more classes today).
        case free(until: Int?)
        /// In class now; `until` is when that class (and any class right after it) ends.
        case inClass(until: Int)
    }

    var id: String
    var name: String
    var state: State
    /// The stretch the bar covers: now to six hours ahead, capped at the end of the waking day.
    var rangeStart: Int
    var rangeEnd: Int
    /// Class time inside the range, merged and in order (the dark parts of the bar).
    var classBlocks: [SnapshotBlock]

    var isFree: Bool {
        if case .free = state { return true }
        return false
    }

    /// "12:15–5:00 PM", or "11:15 AM–2:00 PM" when the range crosses noon.
    var rangeText: String { WidgetFriendStatusEngine.rangeText(rangeStart, rangeEnd) }
}

nonisolated enum WidgetFriendStatusEngine {
    static let lookaheadMinutes = 6 * 60
    /// "3:30–4:45 PM": the first time drops its AM or PM when both share one.
    static func rangeText(_ start: Int, _ end: Int, separator: String = "–") -> String {
        let from = start.clockString, to = end.clockString
        let shortFrom = from.suffix(2) == to.suffix(2) ? String(from.dropLast(3)) : from
        return "\(shortFrom)\(separator)\(to)"
    }

    /// End of the waking day (10 PM), where the bars stop.
    static let dayEndMinutes = 22 * 60

    /// Friends who share a schedule, free first (longest free first), then in class (class ending
    /// soonest first), then by name. A friend with no meetings shared is left out: there is nothing
    /// to judge from, and "free" would be a guess.
    static func rows(at now: Date, friends: [SnapshotFriend], calendar: Calendar = .current) -> [WidgetFriendRow] {
        let weekday = calendar.component(.weekday, from: now)
        let nowMinutes = now.minutesSinceMidnight(in: calendar)
        let rangeEnd = min(dayEndMinutes, nowMinutes + lookaheadMinutes)

        let rows: [WidgetFriendRow] = friends.compactMap { friend in
            guard !friend.blocks.isEmpty else { return nil }
            let today = friend.blocks.filter { $0.weekday == weekday }.sorted { $0.startMinutes < $1.startMinutes }

            let state: WidgetFriendRow.State
            if let current = today.first(where: { $0.startMinutes <= nowMinutes && nowMinutes < $0.endMinutes }) {
                // Back-to-back classes count as one stretch of "in class".
                var end = current.endMinutes
                while let next = today.first(where: { $0.startMinutes <= end && $0.endMinutes > end }) { end = next.endMinutes }
                state = .inClass(until: end)
            } else {
                state = .free(until: today.first { $0.startMinutes > nowMinutes }?.startMinutes)
            }
            return WidgetFriendRow(
                id: friend.id, name: friend.name, state: state,
                rangeStart: nowMinutes, rangeEnd: max(rangeEnd, nowMinutes),
                classBlocks: merged(today, from: nowMinutes, to: rangeEnd, weekday: weekday))
        }

        return rows.sorted { lhs, rhs in
            switch (lhs.state, rhs.state) {
            case let (.free(a), .free(b)):
                let (x, y) = (a ?? .max, b ?? .max)   // no more classes today is the longest free
                return x != y ? x > y : lhs.name < rhs.name
            case let (.inClass(a), .inClass(b)):
                return a != b ? a < b : lhs.name < rhs.name
            case (.free, .inClass): return true
            case (.inClass, .free): return false
            }
        }
    }

    /// Class blocks clipped to [from, to] with overlapping or touching ones joined.
    private static func merged(_ blocks: [SnapshotBlock], from: Int, to: Int, weekday: Int) -> [SnapshotBlock] {
        var result: [SnapshotBlock] = []
        for block in blocks {
            let start = max(block.startMinutes, from), end = min(block.endMinutes, to)
            guard start < end else { continue }
            if let last = result.last, start <= last.endMinutes {
                result[result.count - 1].endMinutes = max(last.endMinutes, end)
            } else {
                result.append(SnapshotBlock(weekday: weekday, startMinutes: start, endMinutes: end))
            }
        }
        return result
    }
}
