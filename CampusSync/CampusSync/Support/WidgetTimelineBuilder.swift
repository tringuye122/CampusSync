//
//  WidgetTimelineBuilder.swift
//  CampusSync
//
//  Pre-builds the widget's timeline entries from the snapshot. Widgets cannot
//  update continuously, so we create one entry at every boundary where what the
//  widget shows changes (a class starting or ending, an invite starting or
//  expiring) and ask WidgetKit to reload after the last one.
//
//  Time handling: the snapshot's `clockOffset` is the demo time override. All
//  content is computed in "virtual" time (real + offset), while the entry `date`
//  WidgetKit sees is real time (virtual - offset). With no override the two are equal.
//
//  Pure logic, no WidgetKit. Must be a member of both the app and widget targets.
//

import Foundation

nonisolated struct WidgetEntryData: Equatable {
    /// When WidgetKit should show this entry (real time).
    var date: Date
    /// The clock the content is computed against (real time + demo offset).
    var virtualNow: Date
    var offset: TimeInterval
    var status: ScheduleStatus
    var topInvite: SnapshotInvite?

    /// Converts a virtual time (e.g. when the next class starts) to real time, for
    /// countdowns that WidgetKit renders against the real clock.
    func real(_ virtual: Date) -> Date {
        virtual.addingTimeInterval(-offset)
    }

    var isEmpty: Bool { status == .noClasses && topInvite == nil }
}

nonisolated struct WidgetTimelinePlan: Equatable {
    var entries: [WidgetEntryData]
    /// Real time at which the widget should ask for a fresh timeline.
    var reloadAt: Date
}

nonisolated enum WidgetTimelineBuilder {
    /// How far ahead entries are pre-built.
    static let horizon: TimeInterval = 36 * 3600
    static let maxEntries = 24

    static func plan(
        snapshot: WidgetSnapshot,
        realNow: Date,
        calendar: Calendar = .current
    ) -> WidgetTimelinePlan {
        let offset = snapshot.clockOffset
        let virtualNow = realNow.addingTimeInterval(offset)
        let horizonEnd = virtualNow.addingTimeInterval(horizon)

        // Every instant at which the display changes.
        var boundaries = Set<Date>()
        let todayStart = calendar.startOfDay(for: virtualNow)
        for dayOffset in 0...2 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: todayStart) else { continue }
            let weekday = calendar.component(.weekday, from: day)
            for meeting in snapshot.meetings where meeting.weekday == weekday {
                boundaries.insert(day.addingTimeInterval(TimeInterval(meeting.startMinutes * 60)))
                boundaries.insert(day.addingTimeInterval(TimeInterval(meeting.endMinutes * 60)))
            }
        }
        for invite in snapshot.invites {
            boundaries.insert(invite.startTime)
            // Expired when now > expiresAt, so the invite disappears one second later.
            boundaries.insert(invite.expiresAt.addingTimeInterval(1))
        }

        let future = boundaries.filter { $0 > virtualNow && $0 <= horizonEnd }.sorted()
        let kept = Array(future.prefix(maxEntries - 1))
        let instants = [virtualNow] + kept

        let entries = instants.map { instant in
            WidgetEntryData(
                date: instant.addingTimeInterval(-offset),
                virtualNow: instant,
                offset: offset,
                status: ScheduleStatusEngine.status(at: instant, meetings: snapshot.meetings, calendar: calendar),
                topInvite: topInvite(in: snapshot.invites, at: instant)
            )
        }

        let reloadVirtual = future.count > kept.count ? (kept.last ?? horizonEnd) : horizonEnd
        return WidgetTimelinePlan(entries: entries, reloadAt: reloadVirtual.addingTimeInterval(-offset))
    }

    /// The soonest invite that has not expired at `time`.
    static func topInvite(in invites: [SnapshotInvite], at time: Date) -> SnapshotInvite? {
        invites
            .filter { time <= $0.expiresAt }
            .min { $0.startTime < $1.startTime }
    }
}
