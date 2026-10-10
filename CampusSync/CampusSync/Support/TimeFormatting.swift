//
//  TimeFormatting.swift
//  CampusSync
//
//  Small time-of-day formatters shared by the app and the widget. Must be a
//  member of both targets (moved here from Models.swift and
//  FreeSlotCalculator.swift so the widget can use them).
//

import Foundation

nonisolated extension Int {
    /// Minutes after midnight rendered as "1:25 PM".
    var clockString: String {
        let hour24 = (self / 60) % 24
        let minute = self % 60
        let hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12
        return String(format: "%d:%02d %@", hour12, minute, hour24 < 12 ? "AM" : "PM")
    }

    /// Minutes rendered as "45 min", "1h 30m" or "3h".
    var durationString: String {
        if self < 60 { return "\(self) min" }
        let hours = self / 60
        let minutes = self % 60
        return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m"
    }

    /// Minutes as the designs write them: "45 min", "3 h", "3 h 15 min".
    var spacedDuration: String {
        if self < 60 { return "\(self) min" }
        let hours = self / 60
        let minutes = self % 60
        return minutes == 0 ? "\(hours) h" : "\(hours) h \(minutes) min"
    }
}
