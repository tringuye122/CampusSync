//
//  ScheduleStatus.swift
//  CampusSync
//
//  "What am I doing right now?" for the Home banner, and later the widget's
//  timeline. It works on SnapshotMeeting so the app and widget share one code
//  path, and it takes `now` as input (always from AppClock). Must stay free of
//  model types so it can be a member of both the app and widget targets.
//

import Foundation

nonisolated enum ScheduleStatus: Equatable {
    /// In a class now. `nextToday` is the following class later today, if any.
    case inClass(meeting: SnapshotMeeting, endsAt: Date, nextToday: SnapshotMeeting?)
    /// Free now, and the next class starts later today.
    case freeBeforeNext(next: SnapshotMeeting, startsAt: Date)
    /// No more classes today; the next one is on a later day.
    case nextClass(next: SnapshotMeeting, startsAt: Date)
    case noClasses
}

nonisolated enum ScheduleStatusEngine {
    static func status(
        at now: Date,
        meetings: [SnapshotMeeting],
        calendar: Calendar = .current
    ) -> ScheduleStatus {
        let weekday = calendar.component(.weekday, from: now)
        let minuteNow = now.minutesSinceMidnight(in: calendar)

        let today = meetings
            .filter { $0.weekday == weekday }
            .sorted { $0.startMinutes < $1.startMinutes }

        if let current = today.first(where: { $0.startMinutes <= minuteNow && minuteNow < $0.endMinutes }) {
            let dayStart = calendar.startOfDay(for: now)
            let endsAt = date(dayStart, plusMinutes: current.endMinutes, calendar: calendar)
            let next = today.first { $0.startMinutes >= current.endMinutes && $0 != current }
            return .inClass(meeting: current, endsAt: endsAt, nextToday: next)
        }

        guard let upcoming = nextClass(after: now, meetings: meetings, calendar: calendar) else {
            return .noClasses
        }
        return calendar.isDate(upcoming.startsAt, inSameDayAs: now)
            ? .freeBeforeNext(next: upcoming.meeting, startsAt: upcoming.startsAt)
            : .nextClass(next: upcoming.meeting, startsAt: upcoming.startsAt)
    }

    /// The first class that starts strictly after `now`, looking up to a week ahead.
    static func nextClass(
        after now: Date,
        meetings: [SnapshotMeeting],
        calendar: Calendar = .current
    ) -> (meeting: SnapshotMeeting, startsAt: Date)? {
        let minuteNow = now.minutesSinceMidnight(in: calendar)
        let todayStart = calendar.startOfDay(for: now)

        for offset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: todayStart) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            let candidates = meetings
                .filter { $0.weekday == weekday && (offset > 0 || $0.startMinutes > minuteNow) }
                .sorted { $0.startMinutes < $1.startMinutes }
            if let first = candidates.first {
                return (first, date(day, plusMinutes: first.startMinutes, calendar: calendar))
            }
        }
        return nil
    }

    private static func date(_ dayStart: Date, plusMinutes minutes: Int, calendar: Calendar) -> Date {
        calendar.date(byAdding: .minute, value: minutes, to: dayStart) ?? dayStart
    }
}
