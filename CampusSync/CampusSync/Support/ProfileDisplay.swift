//
//  ProfileDisplay.swift
//  CampusSync
//
//  Pure helpers for the profile header: avatar initials and the "Free Tue/Thu 12:15–3:30"
//  line. No UI and no persistence, so they are unit-tested directly.
//

import Foundation

enum Initials {
    /// "Justin Nguyen" -> "JN", "Justin" -> "JU", "" -> "?". First letters of the first and last words.
    static func from(_ name: String) -> String {
        let words = name.split(whereSeparator: \.isWhitespace).map(String.init)
        switch words.count {
        case 0: return "?"
        case 1: return String(words[0].prefix(2)).uppercased()
        default: return (String(words[0].prefix(1)) + String(words[words.count - 1].prefix(1))).uppercased()
        }
    }
}

/// The recurring gap between classes shown in the header, e.g. "Free Tue/Thu 12:15–3:30".
enum FreeWindowSummary {
    /// The longest gap that sits BETWEEN two classes (not the free morning before the first class
    /// or the evening after the last), with every weekday on which that exact gap repeats.
    /// Walking time is ignored: this is the plain gap from one class's end to the next one's start.
    static func text(meetings: [ClassMeeting], minimumGapMinutes: Int = FreeSlotSettings.standard.minimumGapMinutes) -> String? {
        struct Gap: Hashable { var start: Int; var end: Int }
        var daysByGap: [Gap: [Weekday]] = [:]

        for day in Weekday.allCases {
            let busy = meetings.filter { $0.weekdays.contains(day) }.sorted { $0.startMinutes < $1.startMinutes }
            var latestEnd: Int?
            for meeting in busy {
                if let end = latestEnd, meeting.startMinutes - end >= minimumGapMinutes {
                    daysByGap[Gap(start: end, end: meeting.startMinutes), default: []].append(day)
                }
                latestEnd = max(latestEnd ?? meeting.endMinutes, meeting.endMinutes)
            }
        }
        // Longest gap wins; if two are the same length, the one that repeats on more days, then the earlier one.
        guard let best = daysByGap.max(by: { lhs, rhs in
            let l = (lhs.key.end - lhs.key.start, lhs.value.count, -lhs.key.start)
            let r = (rhs.key.end - rhs.key.start, rhs.value.count, -rhs.key.start)
            return l < r
        }) else { return nil }

        let days = best.value.sorted { $0.rawValue < $1.rawValue }.map(\.shortLabel).joined(separator: "/")
        return "Free \(days) \(range(best.key.start, best.key.end))"
    }

    /// The designs' compact class time: "11:00–12:15 PM", "1:25–2:40 PM", "9:30–10:45 AM".
    static func classRange(_ start: Int, _ end: Int) -> String {
        func bare(_ minutes: Int) -> String {
            let h = (minutes / 60) % 12 == 0 ? 12 : (minutes / 60) % 12
            return String(format: "%d:%02d", h, minutes % 60)
        }
        return "\(bare(start))–\(bare(end)) \(end < 12 * 60 ? "AM" : "PM")"
    }

    /// "12:15–3:30 PM" when both ends are in the same half of the day, otherwise "11:00 AM–1:15 PM".
    static func rangeWithPeriod(_ start: Int, _ end: Int) -> String {
        let text = range(start, end)
        return (start < 12 * 60) == (end < 12 * 60) ? "\(text) \(end < 12 * 60 ? "AM" : "PM")" : text
    }

    /// "12:15–3:30" when both ends are in the same half of the day, otherwise "11:00 AM–1:15 PM".
    static func range(_ start: Int, _ end: Int) -> String {
        let sameHalf = (start < 12 * 60) == (end < 12 * 60)   // both AM or both PM
        func bare(_ minutes: Int) -> String {
            let h = (minutes / 60) % 12 == 0 ? 12 : (minutes / 60) % 12
            return String(format: "%d:%02d", h, minutes % 60)
        }
        return sameHalf ? "\(bare(start))–\(bare(end))" : "\(start.clockString)–\(end.clockString)"
    }
}
