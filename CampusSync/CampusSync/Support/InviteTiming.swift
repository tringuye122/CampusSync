//
//  InviteTiming.swift
//  CampusSync
//
//  Pure helpers for how invites are grouped and described over time. Every
//  function takes `now` as input (from AppClock), so this is easy to test and
//  the demo time override works.
//

import Foundation

enum InviteSectionKind: Int, CaseIterable, Identifiable {
    case happeningNow, startingSoon, laterToday, upcoming

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .happeningNow: "Happening now"
        case .startingSoon: "Starting soon"
        case .laterToday: "Later today"
        case .upcoming: "Coming up"
        }
    }
}

struct InviteSection: Identifiable {
    let kind: InviteSectionKind
    let invites: [OpenInvite]
    var id: Int { kind.id }
}

enum InviteTiming {
    /// "Starting soon" means within this many minutes.
    static let soonWindowMinutes = 60

    static func kind(
        start: Date,
        now: Date,
        calendar: Calendar = .current
    ) -> InviteSectionKind {
        if start <= now { return .happeningNow }
        if start.timeIntervalSince(now) <= Double(soonWindowMinutes * 60) { return .startingSoon }
        return calendar.isDate(start, inSameDayAs: now) ? .laterToday : .upcoming
    }

    /// Unexpired invites grouped into time sections, soonest first inside each.
    /// Expiry is evaluated here at read time: expired when now > expiresAt.
    static func sections(
        for invites: [OpenInvite],
        now: Date,
        calendar: Calendar = .current
    ) -> [InviteSection] {
        let active = invites.filter { !$0.isExpired(at: now) }
        return InviteSectionKind.allCases.compactMap { kind in
            let matching = active
                .filter { Self.kind(start: $0.startTime, now: now, calendar: calendar) == kind }
                .sorted { $0.startTime < $1.startTime }
            return matching.isEmpty ? nil : InviteSection(kind: kind, invites: matching)
        }
    }

    /// "Happening now · ends in 45 min", "Starts in 20 min", or a day and time for later days.
    static func countdownText(
        start: Date,
        expiresAt: Date,
        now: Date,
        calendar: Calendar = .current
    ) -> String {
        if start <= now {
            return "Happening now · ends in \(minutes(from: now, to: expiresAt).spacedDuration)"
        }
        if calendar.isDate(start, inSameDayAs: now) {
            return "Starts in \(minutes(from: now, to: start).spacedDuration)"
        }
        return "Starts \(start.formatted(.dateTime.weekday(.abbreviated).hour().minute()))"
    }

    /// Whole minutes between two dates, rounded up, never negative.
    static func minutes(from start: Date, to end: Date) -> Int {
        max(0, Int((end.timeIntervalSince(start) / 60).rounded(.up)))
    }
}
