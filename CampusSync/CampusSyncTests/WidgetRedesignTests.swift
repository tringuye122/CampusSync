//
//  WidgetRedesignTests.swift
//  CampusSyncTests
//
//  The widget redesign's logic: who is free or in class, the snapshot's new fields, and the
//  timeline boundaries friends add.
//

import Foundation
import Testing
@testable import CampusSync

struct WidgetRedesignTests {
    private let calendar = Calendar.current

    /// Oct 2026: 13 = Tue (weekday 3), 17 = Sat.
    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    private func hm(_ hour: Int, _ minute: Int = 0) -> Int { hour * 60 + minute }

    private func friend(_ id: String, _ blocks: [(Int, Int)], weekday: Int = 3) -> SnapshotFriend {
        SnapshotFriend(id: id, name: id, blocks: blocks.map { SnapshotBlock(weekday: weekday, startMinutes: $0.0, endMinutes: $0.1) })
    }

    // MARK: Free or in class

    @Test func aFriendIsFreeUntilTheirNextClassOrInClassUntilItEnds() throws {
        let now = date(13, 12, 15)
        let rows = WidgetFriendStatusEngine.rows(at: now, friends: [
            friend("Alex", [(hm(9), hm(10)), (hm(17), hm(18))]),
            friend("Jordan", [(hm(12), hm(13, 30))]),
        ], calendar: calendar)
        #expect(try #require(rows.first { $0.id == "Alex" }).state == .free(until: hm(17)))
        #expect(try #require(rows.first { $0.id == "Jordan" }).state == .inClass(until: hm(13, 30)))
    }

    @Test func noMoreClassesTodayMeansFreeWithNoEndTime() throws {
        let rows = WidgetFriendStatusEngine.rows(at: date(13, 15), friends: [friend("Dee", [(hm(9), hm(10))])], calendar: calendar)
        #expect(try #require(rows.first).state == .free(until: nil))
    }

    @Test func weekendAndOtherDaysCountAsFree() throws {
        let rows = WidgetFriendStatusEngine.rows(at: date(17, 12), friends: [friend("Dee", [(hm(11), hm(13))])], calendar: calendar)
        #expect(try #require(rows.first).state == .free(until: nil))   // the class is on Tuesday
    }

    @Test func backToBackClassesAreOneStretch() throws {
        let rows = WidgetFriendStatusEngine.rows(
            at: date(13, 12, 30), friends: [friend("Fay", [(hm(12), hm(13)), (hm(13), hm(14))])], calendar: calendar)
        #expect(try #require(rows.first).state == .inClass(until: hm(14)))
    }

    @Test func friendsWithNothingSharedAreLeftOut() {
        let rows = WidgetFriendStatusEngine.rows(
            at: date(13, 12), friends: [SnapshotFriend(id: "x", name: "Xi", blocks: [])], calendar: calendar)
        #expect(rows.isEmpty)
    }

    @Test func freeFriendsComeFirstLongestFreeFirstThenInClass() {
        let rows = WidgetFriendStatusEngine.rows(at: date(13, 12, 15), friends: [
            friend("Jordan", [(hm(12), hm(13))]),                     // in class
            friend("Maya", [(hm(15, 30), hm(16))]),                   // free until 3:30
            friend("Alex", [(hm(17), hm(18))]),                       // free until 5:00
            friend("Dee", [(hm(9), hm(10))]),                         // free the rest of today
        ], calendar: calendar)
        #expect(rows.map(\.id) == ["Dee", "Alex", "Maya", "Jordan"])
    }

    // MARK: The bar

    @Test func theBarCoversSixHoursCappedAtTenPMWithMergedClassBlocks() throws {
        let rows = WidgetFriendStatusEngine.rows(at: date(13, 12, 15), friends: [
            friend("Alex", [(hm(11), hm(12, 30)), (hm(12, 30), hm(13)), (hm(17), hm(19))]),
        ], calendar: calendar)
        let row = try #require(rows.first)
        #expect(row.rangeStart == hm(12, 15) && row.rangeEnd == hm(18, 15))
        // 12:15 to 13:00 (clipped, merged) and 17:00 to 18:15 (clipped to the range end).
        #expect(row.classBlocks.map { [$0.startMinutes, $0.endMinutes] } == [[hm(12, 15), hm(13)], [hm(17), hm(18, 15)]])

        let late = WidgetFriendStatusEngine.rows(at: date(13, 20), friends: [friend("Alex", [(hm(9), hm(10))])], calendar: calendar)
        #expect(try #require(late.first).rangeEnd == hm(22))
    }

    @Test func rangeTextDropsTheFirstPeriodWhenItMatches() throws {
        let alex = try #require(WidgetFriendStatusEngine.rows(
            at: date(13, 12, 15), friends: [friend("A", [(hm(9), hm(10))])], calendar: calendar).first)
        #expect(alex.rangeText == "12:15–6:15 PM")
        let morning = try #require(WidgetFriendStatusEngine.rows(
            at: date(13, 9, 15), friends: [friend("A", [(hm(9), hm(10))])], calendar: calendar).first)
        #expect(morning.rangeText == "9:15 AM–3:15 PM")
    }

    // MARK: Snapshot

    @Test func oldSnapshotsWithoutFriendsStillDecode() throws {
        let json = """
        {"version":1,"generatedAt":"2026-10-13T16:00:00Z","clockOffset":0,"meetings":[],"invites":[]}
        """
        let snapshot = try #require(WidgetSnapshot.decode(Data(json.utf8)))
        #expect(snapshot.friends.isEmpty && snapshot.userHandle == nil)
    }

    @Test func friendsAndTheUserRoundTripThroughTheSnapshot() throws {
        var snapshot = WidgetSnapshot.empty
        snapshot.generatedAt = date(13, 12)
        snapshot.userHandle = "justin"
        snapshot.friends = [friend("Maya", [(hm(9), hm(10))])]
        let decoded = try #require(WidgetSnapshot.decode(try snapshot.encoded()))
        #expect(decoded == snapshot)
    }

    @Test @MainActor func snapshotBuilderSharesFriendTimesOnly() throws {
        let friends = SampleData.friends()
        let snapshot = SnapshotBuilder.make(
            classes: [], invites: [], friends: friends, userHandle: "justin", userName: "Justin N",
            now: date(13, 12), clockOffset: 0)
        let first = try #require(snapshot.friends.first)
        let source = try #require(friends.first { $0.id == first.id })
        let expected = source.classes.reduce(0) { $0 + $1.weekdays.count }
        #expect(first.blocks.count == expected)
        #expect(snapshot.userHandle == "justin")
    }

    // MARK: Timeline

    @Test func friendClassBoundariesBecomeTimelineEntries() {
        var snapshot = WidgetSnapshot.empty
        snapshot.friends = [friend("Maya", [(hm(13), hm(14))])]
        let plan = WidgetTimelineBuilder.plan(snapshot: snapshot, realNow: date(13, 12, 30), calendar: calendar)
        let times = plan.entries.map { $0.virtualNow }
        #expect(times.contains(date(13, 13)) && times.contains(date(13, 14)))
        #expect(plan.entries[0].friends.first?.state == .free(until: hm(13)))
        #expect(plan.entries.first { $0.virtualNow == date(13, 13) }?.friends.first?.state == .inClass(until: hm(14)))
    }
}
