//
//  WidgetTests.swift
//  CampusSyncTests
//

import Foundation
import SwiftData
import Testing
@testable import CampusSync

@MainActor
struct WidgetTests {
    private let calendar = Calendar.current

    /// Oct 2026: 13 = Tue, 14 = Wed, 17 = Sat.
    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func demoSnapshot(now: Date, offset: TimeInterval = 0) -> WidgetSnapshot {
        SnapshotBuilder.make(
            classes: SampleData.classes(),
            invites: SampleData.invites(now: now),
            now: now,
            clockOffset: offset
        )
    }

    // MARK: SnapshotBuilder

    @Test func snapshotFlattensClassesAndCapsInvites() {
        let now = date(13, 12, 30)
        var invites = SampleData.invites(now: now)
        invites.append(OpenInvite(
            title: "Old", landmark: .thePit, category: .social,
            startTime: now.addingTimeInterval(-7200), expiresAt: now.addingTimeInterval(-3600),
            hostID: SampleData.mayaID, hostName: "Maya"))
        let snapshot = SnapshotBuilder.make(
            classes: SampleData.classes(), invites: invites, now: now, clockOffset: 0)

        // COMP 523 meets Mon+Wed (2), the other three meet Tue+Thu (6).
        #expect(snapshot.meetings.count == 8)
        #expect(snapshot.invites.count == SnapshotBuilder.maxInvites)
        #expect(!snapshot.invites.contains { $0.title == "Old" })
        #expect(snapshot.invites == snapshot.invites.sorted { $0.startTime < $1.startTime })
        #expect(snapshot.version == WidgetSnapshot.currentVersion)
    }

    // MARK: Timeline plan

    @Test func entriesLandOnEveryBoundaryInOrder() {
        let now = date(13, 12, 30)
        let plan = WidgetTimelineBuilder.plan(snapshot: demoSnapshot(now: now), realNow: now, calendar: calendar)
        let dates = plan.entries.map(\.date)

        #expect(dates.first == now)
        #expect(dates == dates.sorted())
        #expect(Set(dates).count == dates.count)
        #expect(plan.entries.count <= WidgetTimelineBuilder.maxEntries)

        // 12:30 is free before COMP 577.
        guard case let .freeBeforeNext(next, _) = plan.entries[0].status else {
            Issue.record("Expected freeBeforeNext at 12:30")
            return
        }
        #expect(next.courseCode == "COMP 577")

        // An entry exists exactly when COMP 577 starts, and it shows that class.
        let atClassStart = plan.entries.first { $0.date == date(13, 15, 30) }
        guard case let .inClass(meeting, _, _)? = atClassStart?.status else {
            Issue.record("Expected an inClass entry at 3:30 PM")
            return
        }
        #expect(meeting.courseCode == "COMP 577")

        // And one when the last class ends, pointing at tomorrow's class.
        let afterLast = plan.entries.first { $0.date == date(13, 18, 15) }
        guard case let .nextClass(tomorrow, _)? = afterLast?.status else {
            Issue.record("Expected a nextClass entry at 6:15 PM")
            return
        }
        #expect(tomorrow.courseCode == "COMP 523")
    }

    @Test func inviteDropsOutOneSecondAfterItExpires() {
        let now = date(13, 12, 30)
        let snapshot = demoSnapshot(now: now)
        let first = snapshot.invites[0]   // "Quick lunch at Chase", expires at +80 min
        #expect(WidgetTimelineBuilder.topInvite(in: snapshot.invites, at: first.expiresAt)?.id == first.id)
        #expect(WidgetTimelineBuilder.topInvite(in: snapshot.invites, at: first.expiresAt.addingTimeInterval(1))?.id != first.id)

        let plan = WidgetTimelineBuilder.plan(snapshot: snapshot, realNow: now, calendar: calendar)
        let gone = plan.entries.first { $0.date == first.expiresAt.addingTimeInterval(1) }
        #expect(gone != nil)
        #expect(gone?.topInvite?.id != first.id)
    }

    @Test func demoClockOffsetShiftsContentButEntryDatesStayReal() {
        let realNow = date(17, 9, 0)            // a Saturday
        let virtual = date(13, 12, 30)          // "as if it is Tuesday 12:30 PM"
        let offset = virtual.timeIntervalSince(realNow)
        let plan = WidgetTimelineBuilder.plan(
            snapshot: demoSnapshot(now: virtual, offset: offset), realNow: realNow, calendar: calendar)

        let first = plan.entries[0]
        #expect(first.date == realNow)
        #expect(first.virtualNow == virtual)
        guard case let .freeBeforeNext(next, startsAt) = first.status else {
            Issue.record("Expected freeBeforeNext under the override")
            return
        }
        #expect(next.courseCode == "COMP 577")
        // Countdown targets are converted to real time: 3 hours after real now.
        #expect(first.real(startsAt) == realNow.addingTimeInterval(3 * 3600))
        // There is an entry exactly when COMP 577 starts, 3 real hours from now.
        let classEntry = plan.entries.first { $0.date == realNow.addingTimeInterval(3 * 3600) }
        guard case let .inClass(meeting, _, _)? = classEntry?.status else {
            Issue.record("Expected an inClass entry 3 real hours from now")
            return
        }
        #expect(meeting.courseCode == "COMP 577")
    }

    @Test func emptySnapshotGivesOneEmptyEntry() {
        let now = date(13, 12, 30)
        let plan = WidgetTimelineBuilder.plan(snapshot: .empty, realNow: now, calendar: calendar)
        #expect(plan.entries.count == 1)
        #expect(plan.entries[0].isEmpty)
        #expect(plan.reloadAt == now.addingTimeInterval(WidgetTimelineBuilder.horizon))
    }

    // MARK: Router and sync

    @Test func routerOpensTabsFromWidgetLinks() {
        let router = AppRouter()
        router.open(URL(string: "campussync://invites")!)
        #expect(router.selectedTab == .invites)
        router.open(URL(string: "campussync://schedule")!)
        #expect(router.selectedTab == .schedule)
        router.open(URL(string: "https://example.com/clubs")!)
        router.open(URL(string: "campussync://nonsense")!)
        #expect(router.selectedTab == .schedule)
    }

    @Test func syncWidgetCompletesWithoutAppGroupContainer() async {
        let container = SampleData.previewContainer(now: date(13, 12, 30))
        let services = AppServices(context: container.mainContext, retaining: container)
        await services.syncWidget()   // must not crash whether or not the container exists
    }
}
