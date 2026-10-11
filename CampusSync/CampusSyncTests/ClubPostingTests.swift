//
//  ClubPostingTests.swift
//  CampusSyncTests
//
//  Leaving a club, posting and removing club events, and the timetable events (joined clubs'
//  events and RSVP'd invites).
//

import Foundation
import SwiftData
import Testing
@testable import CampusSync

@MainActor
struct ClubPostingTests {
    /// Tuesday, Oct 13 2026, 12:30 PM: the demo moment.
    private var tuesdayNoon: Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 12, minute: 30))!
    }

    private func make() throws -> (LocalClubRepository, UserProfile, ModelContext) {
        let container = SampleData.previewContainer(now: tuesdayNoon)
        let context = container.mainContext
        let user = try context.fetch(FetchDescriptor<UserProfile>()).first!
        // The container must outlive the context; hold it for the test's duration.
        retainedContainers.append(container)
        return (LocalClubRepository(context: context), user, context)
    }
    private var retainedContainers: [ModelContainer] {
        get { Self.held }
        nonmutating set { Self.held = newValue }
    }
    private static var held: [ModelContainer] = []

    // MARK: Leave

    @Test func leavingAFreeClubUnjoinsIt() async throws {
        let (clubs, user, _) = try make()
        try await clubs.joinClub(id: SampleData.aiClubID)
        try await clubs.leaveClub(id: SampleData.aiClubID)
        #expect(!user.joinedClubIDs.contains(SampleData.aiClubID))
    }

    @Test func leavingTheOnlyDuesClubRemovesTheVerifiedBadge() async throws {
        let (clubs, user, _) = try make()
        user.joinedClubIDs = []
        user.isVerifiedMember = false
        try await clubs.payDues(clubID: SampleData.robotsClubID)
        #expect(user.isVerifiedMember)
        try await clubs.leaveClub(id: SampleData.robotsClubID)
        #expect(!user.isVerifiedMember)
        #expect(user.joinedClubIDs.isEmpty)
    }

    @Test func leavingOneDuesClubKeepsTheBadgeWhileAnotherIsPaid() async throws {
        let (clubs, user, _) = try make()
        user.joinedClubIDs = []
        try await clubs.payDues(clubID: SampleData.robotsClubID)
        try await clubs.payDues(clubID: SampleData.appTeamClubID)
        try await clubs.leaveClub(id: SampleData.robotsClubID)
        #expect(user.isVerifiedMember)
        try await clubs.leaveClub(id: SampleData.appTeamClubID)
        #expect(!user.isVerifiedMember)
    }

    // MARK: Post and remove

    private func draft(club: String = SampleData.aiClubID) -> ClubEventDraft {
        ClubEventDraft(clubID: club, title: "Demo night", location: "Davis Library", start: tuesdayNoon.addingTimeInterval(3600))
    }

    @Test func aMemberPostsAnEventThatTakesTheClubsAccessAndDues() async throws {
        let (clubs, user, _) = try make()
        try await clubs.joinClub(id: SampleData.robotsClubID)
        let event = try await clubs.postEvent(draft(club: SampleData.robotsClubID))
        #expect(event.access == .duesRequired && event.duesAmount == 25)
        #expect(event.clubName == "Rams Robotics")
        #expect(event.posterID == user.id)
        #expect(try await clubs.events(now: tuesdayNoon).contains { $0.id == event.id })
    }

    @Test func aNonMemberCannotPost() async throws {
        let (clubs, user, _) = try make()
        user.joinedClubIDs = []
        await #expect(throws: RepositoryError.self) { try await clubs.postEvent(draft()) }
    }

    @Test func onlyThePosterRemovesAnEvent() async throws {
        let (clubs, _, _) = try make()
        try await clubs.joinClub(id: SampleData.aiClubID)
        let mine = try await clubs.postEvent(draft())
        let seeded = try await clubs.events(now: tuesdayNoon).first { $0.posterID.isEmpty }!
        await #expect(throws: RepositoryError.self) { try await clubs.deleteEvent(id: seeded.id) }
        try await clubs.deleteEvent(id: mine.id)
        #expect(try await clubs.events(now: tuesdayNoon).contains { $0.id == mine.id } == false)
    }

    @Test func aDraftMatchesTheLimitsTheRulesEnforce() {
        var valid = draft()
        #expect(valid.isValid)
        valid.title = "   "
        #expect(!valid.isValid)
        valid.title = String(repeating: "x", count: 81)
        #expect(!valid.isValid)
        valid = draft(); valid.location = ""
        #expect(!valid.isValid)
        valid = draft(); valid.details = String(repeating: "x", count: 301)
        #expect(!valid.isValid)
        valid = draft(); valid.clubID = ""
        #expect(!valid.isValid)
    }

    // MARK: Timetable events

    @Test func joinedClubsEventsAndRSVPdInvitesAppearButOthersDoNot() {
        let calendar = Calendar.current
        let clubEvent = ClubEvent(id: "e1", clubID: "joined", clubName: "A", title: "Meeting", details: "", location: "Sitterson Hall",
                                  startTime: tuesdayNoon.addingTimeInterval(3600), access: .public)
        let otherClub = ClubEvent(id: "e2", clubID: "other", clubName: "B", title: "Nope", details: "", location: "X",
                                  startTime: tuesdayNoon.addingTimeInterval(3600), access: .public)
        let going = OpenInvite(id: "i1", title: "Lunch", landmark: .thePit, category: .food,
                               startTime: tuesdayNoon, expiresAt: tuesdayNoon.addingTimeInterval(3600),
                               hostID: "h", hostName: "H", attendeeIDs: ["h", "me"], recipientIDs: ["me"], capacity: 8)
        let notGoing = OpenInvite(id: "i2", title: "Skipped", landmark: .thePit, category: .food,
                                  startTime: tuesdayNoon, expiresAt: tuesdayNoon.addingTimeInterval(3600),
                                  hostID: "h", hostName: "H", attendeeIDs: ["h"], recipientIDs: ["me"], capacity: 8)
        let all = CalendarEvents.build(
            clubEvents: [clubEvent, otherClub], joinedClubIDs: ["joined"],
            invites: [going, notGoing], rsvpedIDs: ["i1"])
        #expect(all.map(\.title) == ["Lunch", "Meeting"])   // sorted by start
        #expect(all.map(\.kind) == [.invite, .club])
        #expect(all.first { $0.kind == .invite }?.place == "The Pit")

        // Shown on Tuesday of the week of "now", not on other days.
        #expect(CalendarEvents.events(all, on: .tue, now: tuesdayNoon, calendar: calendar).count == 2)
        #expect(CalendarEvents.events(all, on: .wed, now: tuesdayNoon, calendar: calendar).isEmpty)
    }

    @Test func onTheWeekendTheTimetableShowsTheComingWeek() {
        let calendar = Calendar.current
        let saturday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 10))!
        let nextMonday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 19))!
        #expect(CalendarEvents.displayedMonday(now: saturday, calendar: calendar) == nextMonday)
        let sunday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 10))!
        #expect(CalendarEvents.displayedMonday(now: sunday, calendar: calendar) == nextMonday)
        let thursday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 10))!
        let monday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12))!
        #expect(CalendarEvents.displayedMonday(now: thursday, calendar: calendar) == monday)
    }
}
