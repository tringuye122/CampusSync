//
//  ClubAvailability.swift
//  CampusSync
//
//  "✓ You are free then" or "✕ Conflicts with LING 460 · 5:00–6:15 PM": does a club event overlap
//  one of my classes? Pure functions on plain values, so the rule is tested without a database.
//

import Foundation

/// A class as the conflict check needs it: weekly times plus the dates the course actually runs.
struct ClassSlot: Equatable {
    var courseCode: String
    var weekdays: [Weekday]
    var startMinutes: Int
    var endMinutes: Int
    var firstDay: Date
    var lastDay: Date

    init(courseCode: String, weekdays: [Weekday], startMinutes: Int, endMinutes: Int, firstDay: Date, lastDay: Date) {
        self.courseCode = courseCode
        self.weekdays = weekdays
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.firstDay = firstDay
        self.lastDay = lastDay
    }

    init(_ cls: ClassSchedule) {
        self.init(
            courseCode: cls.courseCode, weekdays: cls.weekdays, startMinutes: cls.startMinutes,
            endMinutes: cls.endMinutes, firstDay: cls.startDate, lastDay: cls.endDate)
    }
}

enum ClubAvailability: Equatable {
    case free
    case conflict(courseCode: String, startMinutes: Int, endMinutes: Int)

    var isFree: Bool { self == .free }

    /// Compares the event with every class that meets that weekday while the course is running.
    /// A conflict is a real overlap of times. Walking time is not counted here. If more than one
    /// class overlaps, the earliest is reported. Weekend events never conflict (no weekend classes).
    static func check(
        eventStart: Date,
        eventEnd: Date,
        classes: [ClassSlot],
        calendar: Calendar = .current
    ) -> ClubAvailability {
        guard let weekday = Weekday(rawValue: calendar.component(.weekday, from: eventStart)) else { return .free }
        let eventDay = calendar.startOfDay(for: eventStart)
        let startMinute = eventStart.minutesSinceMidnight(in: calendar)
        // An event that runs past midnight is treated as lasting until the end of its first day.
        let endMinute = calendar.isDate(eventEnd, inSameDayAs: eventStart)
            ? eventEnd.minutesSinceMidnight(in: calendar) : 24 * 60

        let overlapping = classes
            .filter { slot in
                slot.weekdays.contains(weekday)
                    && eventDay >= calendar.startOfDay(for: slot.firstDay)
                    && eventDay <= calendar.startOfDay(for: slot.lastDay)
                    && startMinute < slot.endMinutes
                    && slot.startMinutes < endMinute
            }
            .sorted { $0.startMinutes < $1.startMinutes }

        guard let first = overlapping.first else { return .free }
        return .conflict(courseCode: first.courseCode, startMinutes: first.startMinutes, endMinutes: first.endMinutes)
    }
}
