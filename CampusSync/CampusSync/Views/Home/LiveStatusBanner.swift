//
//  LiveStatusBanner.swift
//  CampusSync
//
//  Current or next class with a countdown, plus a gap summary. "Now" always
//  comes from AppClock, so the demo time override works. TimelineView only
//  triggers the per-minute refresh.
//

import SwiftUI

struct LiveStatusBanner: View {
    let meetings: [SnapshotMeeting]
    @Environment(AppClock.self) private var clock

    var body: some View {
        TimelineView(.everyMinute) { _ in
            let now = clock.now
            let content = Self.content(
                for: ScheduleStatusEngine.status(at: now, meetings: meetings),
                now: now
            )
            VStack(alignment: .leading, spacing: 6) {
                Label(content.title, systemImage: content.symbol)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text(content.detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let gap = content.gap {
                    Text(gap)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            .cardStyle()
            .accessibilityElement(children: .combine)
        }
    }

    struct Content: Equatable {
        var title: String
        var detail: String
        var gap: String?
        var symbol: String
    }

    static func content(for status: ScheduleStatus, now: Date) -> Content {
        switch status {
        case let .inClass(meeting, endsAt, nextToday):
            var gap: String?
            if let next = nextToday {
                let free = next.startMinutes - meeting.endMinutes
                gap = free > 0
                    ? "\(free.durationString) free before \(next.courseCode) at \(next.startMinutes.clockString)"
                    : "\(next.courseCode) starts right after at \(next.startMinutes.clockString)"
            }
            return Content(
                title: "In class: \(meeting.courseCode)",
                detail: "Ends in \(minutes(from: now, to: endsAt).durationString) · \(meeting.location)",
                gap: gap,
                symbol: "book.closed.fill"
            )

        case let .freeBeforeNext(next, startsAt):
            return Content(
                title: "\(minutes(from: now, to: startsAt).durationString) free before \(next.courseCode)",
                detail: "Starts at \(next.startMinutes.clockString) · \(next.location)",
                gap: nil,
                symbol: "clock.fill"
            )

        case let .nextClass(next, _):
            let day = Weekday(rawValue: next.weekday)?.shortLabel ?? ""
            return Content(
                title: "No more classes right now",
                detail: "Next: \(next.courseCode), \(day) \(next.startMinutes.clockString)",
                gap: nil,
                symbol: "moon.stars.fill"
            )

        case .noClasses:
            return Content(
                title: "No classes loaded",
                detail: "Load the demo schedule from the Schedule tab.",
                gap: nil,
                symbol: "calendar.badge.plus"
            )
        }
    }

    /// Whole minutes between two dates, rounded up, never negative.
    private static func minutes(from start: Date, to end: Date) -> Int {
        max(0, Int((end.timeIntervalSince(start) / 60).rounded(.up)))
    }
}

#Preview {
    LiveStatusBanner(meetings: SampleData.classes().flatMap(\.snapshotMeetings))
        .padding()
        .background(Theme.screenBackground)
        .environment(AppClock())
}
