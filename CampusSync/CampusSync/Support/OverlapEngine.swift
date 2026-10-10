//
//  OverlapEngine.swift
//  CampusSync
//
//  Mutual free time between me and one friend. Pure functions, no persistence, no clock
//  of their own (callers pass `now`), so the views, view models and tests share them.
//
//  How the overlap works: each person's free slots come from FreeSlotCalculator, which
//  already applies the waking-hours window (8 AM to 10 PM), the minimum usable gap
//  (30 min) and the walking buffer between buildings. The mutual windows are the
//  intersections of the two lists, day by day.
//

import Foundation

/// A weekly recurring stretch of time when both people are free.
nonisolated struct OverlapWindow: Identifiable, Hashable {
    var weekday: Weekday
    var startMinutes: Int
    var endMinutes: Int

    var id: String { "\(weekday.rawValue)-\(startMinutes)-\(endMinutes)" }
    var durationMinutes: Int { endMinutes - startMinutes }
}

nonisolated enum OverlapEngine {
    /// Mutual free windows, longest first (then earlier in the week, then earlier in the day).
    /// An intersection shorter than the minimum gap is dropped: two 40-minute gaps that only
    /// share 10 minutes are not a usable meetup time.
    static func mutualFreeWindows(
        mine: [ClassMeeting],
        theirs: [ClassMeeting],
        settings: FreeSlotSettings = .standard
    ) -> [OverlapWindow] {
        var windows: [OverlapWindow] = []
        for day in Weekday.allCases {
            let mySlots = FreeSlotCalculator.freeSlots(on: day, meetings: mine, settings: settings)
            let theirSlots = FreeSlotCalculator.freeSlots(on: day, meetings: theirs, settings: settings)

            // Both lists are sorted by start and never overlap themselves, so a two-pointer
            // sweep finds every intersection: take the overlap of the pair under the pointers,
            // then advance whichever slot ends first.
            var i = 0
            var j = 0
            while i < mySlots.count, j < theirSlots.count {
                let start = max(mySlots[i].startMinutes, theirSlots[j].startMinutes)
                let end = min(mySlots[i].endMinutes, theirSlots[j].endMinutes)
                if end - start >= settings.minimumGapMinutes {
                    windows.append(OverlapWindow(weekday: day, startMinutes: start, endMinutes: end))
                }
                if mySlots[i].endMinutes < theirSlots[j].endMinutes { i += 1 } else { j += 1 }
            }
        }
        return windows.sorted {
            ($1.durationMinutes, $0.weekday.rawValue, $0.startMinutes)
                < ($0.durationMinutes, $1.weekday.rawValue, $1.startMinutes)
        }
    }

    /// The next real date an invite for `window` can start. The window repeats weekly, so:
    /// - a later day this week starts at the window's start;
    /// - today, before the window, starts at the window's start;
    /// - today, during the window, starts at `now` rounded up to 5 minutes, if at least
    ///   `minimumMinutes` of the window remain;
    /// - otherwise the same weekday next week.
    static func nextStart(
        of window: OverlapWindow,
        after now: Date,
        calendar: Calendar = .current,
        minimumMinutes: Int = FreeSlotSettings.standard.minimumGapMinutes
    ) -> Date? {
        let today = calendar.startOfDay(for: now)
        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                  calendar.component(.weekday, from: day) == window.weekday.rawValue,
                  let windowStart = calendar.date(byAdding: .minute, value: window.startMinutes, to: day),
                  let windowEnd = calendar.date(byAdding: .minute, value: window.endMinutes, to: day)
            else { continue }

            let start = max(windowStart, roundedUpToFiveMinutes(now))
            if windowEnd.timeIntervalSince(start) >= Double(minimumMinutes * 60) {
                return start
            }
        }
        return nil
    }

    private static func roundedUpToFiveMinutes(_ date: Date) -> Date {
        Date(timeIntervalSinceReferenceDate: (date.timeIntervalSinceReferenceDate / 300).rounded(.up) * 300)
    }
}
