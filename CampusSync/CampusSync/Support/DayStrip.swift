//
//  DayStrip.swift
//  CampusSync
//
//  The data behind the Home "Friends free now" bars: for one weekday and a time range, where
//  I am in class, where my friend is in class, and where we are BOTH free. Pure values, so the
//  view only draws rectangles and the tests check the numbers.
//

import Foundation

struct StripSegment: Equatable, Hashable {
    var start: Int   // minutes after midnight
    var end: Int
    var length: Int { end - start }
}

struct DayStrip: Equatable {
    var rangeStart: Int
    var rangeEnd: Int
    /// Class time (busy), clipped to the range and merged. Everything else is free.
    var mine: [StripSegment]
    var theirs: [StripSegment]
    /// Mutual free windows (from OverlapEngine), clipped to the range.
    var both: [StripSegment]

    static func make(
        mine: [ClassMeeting],
        theirs: [ClassMeeting],
        on weekday: Weekday,
        from rangeStart: Int,
        to rangeEnd: Int,
        settings: FreeSlotSettings = .standard
    ) -> DayStrip {
        let windows = OverlapEngine.mutualFreeWindows(mine: mine, theirs: theirs, settings: settings)
            .filter { $0.weekday == weekday }
            .compactMap { clip(StripSegment(start: $0.startMinutes, end: $0.endMinutes), rangeStart, rangeEnd) }
            .sorted { $0.start < $1.start }   // OverlapEngine returns longest first; the strip is in time order
        return DayStrip(
            rangeStart: rangeStart,
            rangeEnd: rangeEnd,
            mine: busy(mine, on: weekday, rangeStart, rangeEnd),
            theirs: busy(theirs, on: weekday, rangeStart, rangeEnd),
            both: windows
        )
    }

    /// Class meetings on `weekday`, clipped to the range and merged where they touch or overlap.
    private static func busy(_ meetings: [ClassMeeting], on weekday: Weekday, _ lo: Int, _ hi: Int) -> [StripSegment] {
        let clipped = meetings
            .filter { $0.weekdays.contains(weekday) }
            .compactMap { clip(StripSegment(start: $0.startMinutes, end: $0.endMinutes), lo, hi) }
            .sorted { $0.start < $1.start }
        var merged: [StripSegment] = []
        for segment in clipped {
            if let last = merged.last, segment.start <= last.end {
                merged[merged.count - 1].end = max(last.end, segment.end)
            } else {
                merged.append(segment)
            }
        }
        return merged
    }

    private static func clip(_ segment: StripSegment, _ lo: Int, _ hi: Int) -> StripSegment? {
        let clipped = StripSegment(start: max(segment.start, lo), end: min(segment.end, hi))
        return clipped.length > 0 ? clipped : nil
    }
}
