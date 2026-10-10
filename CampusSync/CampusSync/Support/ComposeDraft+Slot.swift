//
//  ComposeDraft+Slot.swift
//  CampusSync
//
//  "Make an invite for this slot": a compose draft prefilled from a mutual free window.
//

import Foundation

extension ComposeDraft {
    /// Default invite length when starting from a free slot.
    static let slotDefaultMinutes = 60

    /// A draft that starts at the window's next start and lasts 60 minutes, or the longest
    /// duration option that still fits if the rest of the window is shorter. Only the friend
    /// from the overlap view is invited; the poster can still change everything before posting.
    /// Nil if the window has no usable time left.
    static func forSlot(
        _ window: OverlapWindow,
        friendID: String,
        now: Date,
        calendar: Calendar = .current
    ) -> ComposeDraft? {
        guard let start = OverlapEngine.nextStart(of: window, after: now, calendar: calendar),
              let windowEnd = calendar.date(
                byAdding: .minute, value: window.endMinutes, to: calendar.startOfDay(for: start))
        else { return nil }

        let remaining = Int(windowEnd.timeIntervalSince(start) / 60)
        let fitting = durationOptions.filter { $0 <= min(slotDefaultMinutes, remaining) }.max()
        guard let duration = fitting else { return nil }

        var draft = ComposeDraft(startTime: start, recipientIDs: [friendID])
        draft.durationMinutes = duration
        return draft
    }
}
