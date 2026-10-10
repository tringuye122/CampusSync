//
//  OverlapTests.swift
//  CampusSyncTests
//
//  Mutual free time: the intersection math, the next real date for a weekly window, the
//  "Make an invite for this slot" defaults, and the view model's states.
//

import Foundation
import SwiftData
import Testing
@testable import CampusSync

@MainActor
struct OverlapTests {
    private func meeting(
        _ day: Weekday, _ start: Int, _ end: Int, _ building: String = "A", code: String = "X 1"
    ) -> ClassMeeting {
        ClassMeeting(courseCode: code, weekdays: [day], startMinutes: start, endMinutes: end, building: building)
    }

    private func hm(_ hour: Int, _ minute: Int = 0) -> Int { hour * 60 + minute }

    // MARK: Intersection math

    @Test func twoEmptySchedulesAreFreeAllWakingHoursEveryDay() {
        let windows = OverlapEngine.mutualFreeWindows(mine: [], theirs: [])
        #expect(windows.count == 5)
        #expect(windows.allSatisfy { $0.startMinutes == hm(8) && $0.endMinutes == hm(22) })
        #expect(windows.map(\.weekday) == Weekday.allCases)   // equal lengths: earlier in the week first
    }

    @Test func windowsAreTheIntersectionOfBothFreeLists() {
        // Mine: Monday class 9:00 to 10:00. Theirs: Monday class 9:30 to 11:00.
        // I am free 8:00-9:00 and 10:00-22:00; they are free 8:00-9:30 and 11:00-22:00.
        let windows = OverlapEngine.mutualFreeWindows(
            mine: [meeting(.mon, hm(9), hm(10))],
            theirs: [meeting(.mon, hm(9, 30), hm(11))])
        let monday = windows.filter { $0.weekday == .mon }
        #expect(monday.map(\.startMinutes) == [hm(11), hm(8)])        // 11-22 (11h), then 8-9 (1h)
        #expect(monday.map(\.endMinutes) == [hm(22), hm(9)])
    }

    @Test func longestWindowsComeFirst() {
        let windows = OverlapEngine.mutualFreeWindows(
            mine: [meeting(.mon, hm(9), hm(10))], theirs: [meeting(.mon, hm(9, 30), hm(11))])
        let durations = windows.map(\.durationMinutes)
        #expect(durations == durations.sorted(by: >))
        #expect(windows.last?.weekday == .mon && windows.last?.durationMinutes == 60)
    }

    @Test func anOverlapShorterThanTheMinimumGapIsDropped() {
        // I am only free 8:00-8:45 on Wednesday; they are only free from 8:20. Shared: 25 min.
        let windows = OverlapEngine.mutualFreeWindows(
            mine: [meeting(.wed, hm(8, 45), hm(22))],
            theirs: [meeting(.wed, hm(8), hm(8, 20))])
        #expect(!windows.contains { $0.weekday == .wed })
    }

    @Test func eachPersonsWalkingBufferIsApplied() {
        // My gap between two different buildings (10:00-11:00) loses 10 minutes at each end.
        let windows = OverlapEngine.mutualFreeWindows(
            mine: [meeting(.thu, hm(8), hm(10), "A"), meeting(.thu, hm(11), hm(22), "B")],
            theirs: [])
        let thursday = windows.filter { $0.weekday == .thu }
        #expect(thursday == [OverlapWindow(weekday: .thu, startMinutes: hm(10, 10), endMinutes: hm(10, 50))])
    }

    @Test func settingsAreRespected() {
        var settings = FreeSlotSettings.standard
        settings.minimumGapMinutes = 90
        let windows = OverlapEngine.mutualFreeWindows(
            mine: [meeting(.fri, hm(9), hm(10))], theirs: [meeting(.fri, hm(9, 30), hm(11))], settings: settings)
        // The 8:00-9:00 sliver (60 min) is below the 90 minute minimum.
        #expect(!windows.contains { $0.weekday == .fri && $0.durationMinutes < 90 })
    }

    @Test func demoUserAndSeedFriendsShareTheTuesdayGap() throws {
        // The seed friends are built to overlap the Tue/Thu 12:15 to 3:30 PM gap (spec section 7).
        let mine = SampleData.classes().map(\.meeting)
        let friend = try #require(SampleData.friends().first)
        let windows = OverlapEngine.mutualFreeWindows(mine: mine, theirs: friend.classes)
        #expect(windows.contains {
            $0.weekday == .tue && $0.startMinutes <= hm(12, 15) + 10 && $0.endMinutes >= hm(15, 30) - 10
        })
    }

    // MARK: Next real date for a weekly window

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    // October 2026: Sat 10th, Tue 13th, Tue 20th.
    private let tuesdayLunch = OverlapWindow(weekday: .tue, startMinutes: 12 * 60 + 15, endMinutes: 15 * 60 + 30)

    @Test func aLaterDayStartsAtTheWindowStart() {
        let start = OverlapEngine.nextStart(of: tuesdayLunch, after: date(10, 10), calendar: calendar)
        #expect(start == date(13, 12, 15))
    }

    @Test func todayBeforeTheWindowStartsAtTheWindowStart() {
        let start = OverlapEngine.nextStart(of: tuesdayLunch, after: date(13, 11), calendar: calendar)
        #expect(start == date(13, 12, 15))
    }

    @Test func todayDuringTheWindowStartsNowRoundedUpToFiveMinutes() {
        let start = OverlapEngine.nextStart(of: tuesdayLunch, after: date(13, 13, 2), calendar: calendar)
        #expect(start == date(13, 13, 5))
    }

    @Test func todayWithTooLittleLeftMovesToNextWeek() {
        // 3:10 PM leaves 20 minutes, under the 30 minute minimum.
        let start = OverlapEngine.nextStart(of: tuesdayLunch, after: date(13, 15, 10), calendar: calendar)
        #expect(start == date(20, 12, 15))
    }

    // MARK: Invite defaults

    @Test func slotDraftIsSixtyMinutesForOnlyThatFriend() throws {
        let draft = try #require(ComposeDraft.forSlot(tuesdayLunch, friendID: "maya", now: date(10, 10), calendar: calendar))
        #expect(draft.startTime == date(13, 12, 15))
        #expect(draft.durationMinutes == 60)
        #expect(draft.recipientIDs == ["maya"])
        #expect(draft.canPost)
    }

    @Test func slotDraftShrinksToWhatFits() throws {
        let short = OverlapWindow(weekday: .tue, startMinutes: 9 * 60, endMinutes: 9 * 60 + 45)
        #expect(try #require(ComposeDraft.forSlot(short, friendID: "m", now: date(10, 10), calendar: calendar)).durationMinutes == 30)
        // 40 minutes left of the lunch window.
        let late = try #require(ComposeDraft.forSlot(tuesdayLunch, friendID: "m", now: date(13, 14, 48), calendar: calendar))
        #expect(late.startTime == date(13, 14, 50))
        #expect(late.durationMinutes == 30)
    }

    @Test func slotDraftExpiryIsStartPlusDuration() throws {
        let draft = try #require(ComposeDraft.forSlot(tuesdayLunch, friendID: "m", now: date(10, 10), calendar: calendar))
        let invite = draft.makeInvite(hostID: "me", hostName: "Me")
        #expect(invite.expiresAt == date(13, 13, 15))
        #expect(invite.recipientIDs == ["m"])
    }

    // MARK: View model

    @Test func viewModelListsWindowsForTheFirstFriendAndOffersAnInvite() async throws {
        let services = AppServices.preview()
        let viewModel = FriendOverlapViewModel()
        await viewModel.load(services: services)
        #expect(viewModel.selectedFriend != nil)
        guard case .ready = viewModel.state else {
            Issue.record("expected ready, got \(viewModel.state)")
            return
        }
        let window = try #require(viewModel.windows.first)
        viewModel.startInvite(for: window, now: AppClock().now)
        let draft = try #require(viewModel.composeDraft)
        #expect(draft.recipientIDs == [try #require(viewModel.selectedFriendID)])
        #expect(draft.durationMinutes <= 60)
    }

    @Test func viewModelPostsTheInviteToTheFriend() async throws {
        let services = AppServices.preview()
        let viewModel = FriendOverlapViewModel()
        await viewModel.load(services: services)
        let window = try #require(viewModel.windows.first)
        viewModel.startInvite(for: window, now: AppClock().now)
        let draft = try #require(viewModel.composeDraft)

        #expect(await viewModel.post(draft, services: services))
        #expect(viewModel.postedToName == viewModel.selectedFriend?.displayName)
        let invites = try await services.invites.activeInvites(now: AppClock().now)
        #expect(invites.contains { $0.recipientIDs == draft.recipientIDs.map { $0 } && $0.hostID == SampleData.userID })
    }

    @Test func aFriendWithNoSharedClassesIsNotShownAsFreeAllDay() async throws {
        let services = AppServices.preview()
        let viewModel = FriendOverlapViewModel()
        await viewModel.load(services: services)
        let empty = try #require(viewModel.friends.first)
        empty.classes = []   // they have not imported a schedule, or turned sharing off
        viewModel.selectedFriendID = empty.id
        #expect(viewModel.state == .friendHasNoSchedule(name: empty.displayName))
        #expect(viewModel.windows.isEmpty)
    }

    @Test func noFriendsAndNoOwnScheduleHaveTheirOwnStates() async throws {
        let services = AppServices.preview()
        let viewModel = FriendOverlapViewModel()
        try await services.schedule.replaceClasses(with: [])
        await viewModel.load(services: services)
        #expect(viewModel.state == .noOwnSchedule)

        let lonely = AppServices.preview()
        try await lonely.store.wipe()
        lonely.store.context.insert(UserProfile(id: "solo", displayName: "Solo", handle: "solo"))
        try lonely.store.context.save()
        let lonelyModel = FriendOverlapViewModel()
        await lonelyModel.load(services: lonely)
        #expect(lonelyModel.state == .noFriends)
    }
}
