//
//  LiveStatusBanner.swift
//  CampusSync
//
//  The blue "FREE NOW" hero card at the top of Home: free time until the next class, or the
//  class you are in. "Now" always comes from AppClock, so the demo time override works.
//  TimelineView only triggers the per-minute refresh.
//

import SwiftUI

struct LiveStatusBanner: View {
    let meetings: [SnapshotMeeting]
    @Environment(AppClock.self) private var clock

    var body: some View {
        TimelineView(.everyMinute) { _ in
            let now = clock.now
            let weekday = Calendar.current.component(.weekday, from: now)
            let content = Self.content(
                for: ScheduleStatusEngine.status(at: now, meetings: meetings),
                now: now,
                hasClassesToday: meetings.contains { $0.weekday == weekday }
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(content.label)
                    .font(.subheadline.weight(.heavy))
                    .tracking(1)
                    .foregroundStyle(Theme.navy)
                Text(content.headline)
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .foregroundStyle(Theme.navy)
                Text(content.detail)
                    .font(.headline)
                    .foregroundStyle(Theme.navy)
                if let extra = content.extra {
                    Text(extra)
                        .font(.subheadline)
                        .foregroundStyle(Theme.navy)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Carolina Blue in both appearances; Navy text on it is readable in light and dark mode.
            .background(Theme.carolinaBlue, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }

    struct Content: Equatable {
        /// Small caps line: "FREE NOW", "IN CLASS".
        var label: String
        /// The big line: a countdown ("3 h 15 min") or the class code.
        var headline: String
        var detail: String
        var extra: String?
    }

    static func content(for status: ScheduleStatus, now: Date, hasClassesToday: Bool = true) -> Content {
        switch status {
        case let .inClass(meeting, endsAt, nextToday):
            var extra: String?
            if let next = nextToday {
                let free = next.startMinutes - meeting.endMinutes
                extra = free > 0
                    ? "Then \(free.spacedDuration) free before \(next.courseCode) at \(next.startMinutes.clockString)"
                    : "\(next.courseCode) starts right after at \(next.startMinutes.clockString)"
            }
            return Content(
                label: "IN CLASS",
                headline: meeting.courseCode,
                detail: "Ends in \(minutes(from: now, to: endsAt).spacedDuration) · \(meeting.location)",
                extra: extra)

        case let .freeBeforeNext(next, startsAt):
            return Content(
                label: "FREE NOW",
                headline: minutes(from: now, to: startsAt).spacedDuration,
                detail: "Next: \(next.courseCode) at \(next.startMinutes.clockString) · \(next.location)",
                extra: nil)

        case let .nextClass(next, _):
            let day = Weekday(rawValue: next.weekday)?.shortLabel ?? ""
            return Content(
                label: hasClassesToday ? "DONE FOR TODAY" : "NO CLASSES TODAY",
                headline: hasClassesToday ? "Free the rest of the day" : "Free all day",
                detail: "Next: \(next.courseCode), \(day) \(next.startMinutes.clockString) · \(next.location)",
                extra: nil)

        case .noClasses:
            return Content(
                label: "NO CLASSES YET",
                headline: "Add your schedule",
                detail: "Import your ConnectCarolina PDF or load the demo schedule in the Schedule tab.",
                extra: nil)
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
