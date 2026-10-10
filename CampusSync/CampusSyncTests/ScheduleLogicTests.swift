//
//  ScheduleLogicTests.swift
//  CampusSyncTests
//

import Foundation
import Testing
@testable import CampusSync

struct ScheduleLogicTests {
    private let calendar = Calendar.current

    /// Oct 2026: 13 = Tue, 14 = Wed, 17 = Sat, 19 = Mon.
    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private var demoMeetings: [ClassMeeting] { SampleData.classes().map(\.meeting) }

    // MARK: Free slots

    @Test func demoTuesdayHasTheBigGapAndDropsTheScramble() {
        let slots = FreeSlotCalculator.freeSlots(on: .tue, meetings: demoMeetings)
        let ranges = slots.map { [$0.startMinutes, $0.endMinutes] }
        #expect(ranges == [
            [8 * 60, 11 * 60],              // before COMP 433
            [12 * 60 + 15, 15 * 60 + 30],   // 3h 15m, Sitterson to Sitterson so no walking trim
            [18 * 60 + 15, 22 * 60],        // after LING 460
        ])
        #expect(slots[1].label == "3h 15m free")
    }

    @Test func mondayIsFreeUntilFirstClassAndFridayIsAllFree() {
        let monday = FreeSlotCalculator.freeSlots(on: .mon, meetings: demoMeetings)
        #expect(monday.first?.startMinutes == 8 * 60)
        #expect(monday.first?.endMinutes == 13 * 60 + 25)
        let friday = FreeSlotCalculator.freeSlots(on: .fri, meetings: demoMeetings)
        #expect(friday.count == 1)
        #expect(friday[0].durationMinutes == 14 * 60)
    }

    @Test func walkingBufferTrimsGapsBetweenDifferentBuildings() {
        let a = ClassMeeting(courseCode: "A", weekdays: [.mon], startMinutes: 9 * 60,
                             endMinutes: 10 * 60, building: "Sitterson Hall")
        let b = ClassMeeting(courseCode: "B", weekdays: [.mon], startMinutes: 11 * 60,
                             endMinutes: 12 * 60, building: "Fetzer Hall")
        let slots = FreeSlotCalculator.freeSlots(on: .mon, meetings: [a, b])
        #expect(slots.contains { $0.startMinutes == 10 * 60 + 10 && $0.endMinutes == 10 * 60 + 50 })

        // A 40 minute gap shrinks to 20 after walking time, below the 30 minute minimum.
        let tight = ClassMeeting(courseCode: "C", weekdays: [.mon], startMinutes: 10 * 60 + 40,
                                 endMinutes: 11 * 60 + 30, building: "Fetzer Hall")
        let tightSlots = FreeSlotCalculator.freeSlots(on: .mon, meetings: [a, tight])
        #expect(!tightSlots.contains { $0.startMinutes >= 10 * 60 && $0.endMinutes <= 10 * 60 + 40 })
    }

    @Test func overlappingClassesDoNotCreatePhantomGaps() {
        let long = ClassMeeting(courseCode: "L", weekdays: [.mon], startMinutes: 9 * 60,
                                endMinutes: 12 * 60, building: "X")
        let inside = ClassMeeting(courseCode: "I", weekdays: [.mon], startMinutes: 10 * 60,
                                  endMinutes: 11 * 60, building: "X")
        let slots = FreeSlotCalculator.freeSlots(on: .mon, meetings: [long, inside])
        #expect(slots.map(\.startMinutes) == [8 * 60, 12 * 60])
    }

    // MARK: Status

    private var snapshotMeetings: [SnapshotMeeting] {
        SampleData.classes().flatMap(\.snapshotMeetings)
    }

    @Test func tuesdayLunchtimeIsFreeBeforeComp577() {
        let status = ScheduleStatusEngine.status(at: date(13, 12, 30), meetings: snapshotMeetings)
        guard case let .freeBeforeNext(next, startsAt) = status else {
            Issue.record("Expected freeBeforeNext, got \(status)")
            return
        }
        #expect(next.courseCode == "COMP 577")
        #expect(startsAt == date(13, 15, 30))
    }

    @Test func duringClassReportsEndAndFollowingClass() {
        let status = ScheduleStatusEngine.status(at: date(13, 11, 30), meetings: snapshotMeetings)
        guard case let .inClass(meeting, endsAt, nextToday) = status else {
            Issue.record("Expected inClass, got \(status)")
            return
        }
        #expect(meeting.courseCode == "COMP 433")
        #expect(endsAt == date(13, 12, 15))
        #expect(nextToday?.courseCode == "COMP 577")
    }

    @Test func afterLastClassPointsAtNextDay() {
        let status = ScheduleStatusEngine.status(at: date(13, 19, 0), meetings: snapshotMeetings)
        guard case let .nextClass(next, startsAt) = status else {
            Issue.record("Expected nextClass, got \(status)")
            return
        }
        #expect(next.courseCode == "COMP 523")
        #expect(startsAt == date(14, 13, 25))
    }

    @Test func weekendPointsAtMonday() {
        let status = ScheduleStatusEngine.status(at: date(17, 10, 0), meetings: snapshotMeetings)
        guard case let .nextClass(next, startsAt) = status else {
            Issue.record("Expected nextClass, got \(status)")
            return
        }
        #expect(next.courseCode == "COMP 523")
        #expect(startsAt == date(19, 13, 25))
    }

    @Test func noMeetingsMeansNoClasses() {
        #expect(ScheduleStatusEngine.status(at: date(13, 12, 0), meetings: []) == .noClasses)
    }

    // MARK: Banner copy

    @Test func bannerSummarisesTheGap() {
        let now = date(13, 12, 30)
        let status = ScheduleStatusEngine.status(at: now, meetings: snapshotMeetings)
        let content = LiveStatusBanner.content(for: status, now: now)
        #expect(content.label == "FREE NOW")
        #expect(content.headline == "3 h")
        #expect(content.detail.hasPrefix("Next: COMP 577 at 3:30 PM"))
        let early = date(13, 10, 15)
        let beforeClass = LiveStatusBanner.content(
            for: ScheduleStatusEngine.status(at: early, meetings: snapshotMeetings), now: early)
        #expect(beforeClass.headline == "45 min")
        #expect(beforeClass.detail.hasPrefix("Next: COMP 433 at 11:00 AM"))
    }
}
