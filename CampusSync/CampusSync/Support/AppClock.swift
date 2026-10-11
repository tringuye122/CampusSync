//
//  AppClock.swift
//  CampusSync
//
//  The one clock. Every "now" in the app and widget goes through here; nothing
//  else may call Date(). The demo needs "as if it is Tuesday 12:30 PM".
//  Must be a member of both the app and widget targets.
//

import Foundation
import Observation
import SwiftUI

@Observable
final class AppClock {
    /// Seconds added to the real time. Zero means real time.
    private(set) var offset: TimeInterval = 0

    var now: Date { Self.now(offset: offset) }
    var isOverridden: Bool { offset != 0 }

    init(offset: TimeInterval = 0) {
        self.offset = offset
    }

    /// Makes `now` read as `date`, then keeps ticking forward normally.
    func setOverride(to date: Date) {
        offset = date.timeIntervalSince(Self.now(offset: 0))
    }

    func clearOverride() {
        offset = 0
    }

    /// The only Date() call in the codebase. The widget calls this with the
    /// snapshot's `clockOffset`.
    nonisolated static func now(offset: TimeInterval) -> Date {
        Date().addingTimeInterval(offset)
    }
}

// MARK: - Calendar helpers (pure; take the date as input)

nonisolated extension Date {
    /// Minutes after midnight in the given calendar.
    func minutesSinceMidnight(in calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: self)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// Calendar weekday number (Sunday = 1), same numbering as `Weekday.rawValue`.
    func weekdayValue(in calendar: Calendar = .current) -> Int {
        calendar.component(.weekday, from: self)
    }
}
