//
//  FreeSlotCalculator.swift
//  CampusSync
//
//  Turns a weekly class list into usable free time. Pure logic, no clock and no
//  storage, so the timetable, the Friend Overlap view and tests all share it.
//

import Foundation

struct FreeSlotSettings: Equatable {
    /// Gaps shorter than this are not usable free time.
    var minimumGapMinutes = 30
    /// Waking-hours window, minutes after midnight (8 AM to 10 PM).
    var dayStartMinutes = 8 * 60
    var dayEndMinutes = 22 * 60
    /// Walking time. Trimmed from BOTH ends of a gap that sits between two classes
    /// in different buildings. Gaps before the first class or after the last are untouched.
    var walkingBufferMinutes = 10

    static let standard = FreeSlotSettings()
}

enum FreeSlotCalculator {
    /// Free slots for every weekday, ordered by weekday then start time.
    static func freeSlots(
        for meetings: [ClassMeeting],
        settings: FreeSlotSettings = .standard
    ) -> [FreeSlot] {
        Weekday.allCases.flatMap { freeSlots(on: $0, meetings: meetings, settings: settings) }
    }

    static func freeSlots(
        on weekday: Weekday,
        meetings: [ClassMeeting],
        settings: FreeSlotSettings = .standard
    ) -> [FreeSlot] {
        let busy = meetings
            .filter { $0.weekdays.contains(weekday) }
            .sorted { $0.startMinutes < $1.startMinutes }

        var slots: [FreeSlot] = []
        var cursor = settings.dayStartMinutes
        // Building of the class that ends latest so far; nil before the first class.
        var previousBuilding: String?

        func addGap(from start: Int, to end: Int) {
            guard end > start else { return }
            let duration = end - start
            guard duration >= settings.minimumGapMinutes else { return }
            slots.append(FreeSlot(
                weekday: weekday,
                startMinutes: start,
                endMinutes: end,
                label: "\(duration.durationString) free"
            ))
        }

        for meeting in busy {
            var gapStart = cursor
            var gapEnd = min(meeting.startMinutes, settings.dayEndMinutes)

            // Walking time applies only when the gap sits between two different buildings.
            if let previous = previousBuilding,
               previous.caseInsensitiveCompare(meeting.building) != .orderedSame {
                gapStart += settings.walkingBufferMinutes
                gapEnd -= settings.walkingBufferMinutes
            }
            addGap(from: gapStart, to: gapEnd)

            if meeting.endMinutes >= cursor {
                cursor = meeting.endMinutes
                previousBuilding = meeting.building
            }
        }

        // After the last class: no walking needed.
        addGap(from: cursor, to: settings.dayEndMinutes)
        return slots
    }
}

extension Int {
    /// Minutes rendered as "45 min", "1h 30m" or "3h".
    var durationString: String {
        if self < 60 { return "\(self) min" }
        let hours = self / 60
        let minutes = self % 60
        return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
    }
}
