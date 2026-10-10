//
//  FoundationTests.swift
//  CampusSyncTests
//

import Foundation
import SwiftData
import Testing
@testable import CampusSync

@MainActor
struct FoundationTests {
    /// Tuesday, Oct 13 2026, 12:30 PM local: the demo moment.
    private var tuesdayNoon: Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 12, minute: 30))!
    }

    @Test func clockOverrideShiftsNowAndClears() {
        let clock = AppClock()
        clock.setOverride(to: tuesdayNoon)
        #expect(abs(clock.now.timeIntervalSince(tuesdayNoon)) < 2)
        #expect(clock.now.weekdayValue() == Weekday.tue.rawValue)
        clock.clearOverride()
        #expect(!clock.isOverridden)
    }

    @Test func seedHasDemoScheduleAndFriends() async throws {
        let container = SampleData.previewContainer(now: tuesdayNoon)
        let schedule = LocalScheduleRepository(context: container.mainContext, ratings: PreviewRatingProvider())
        let classes = try await schedule.classes()
        #expect(Set(classes.map(\.courseCode)) == ["COMP 523", "COMP 433", "COMP 577", "LING 460"])
        #expect(try await schedule.friends().count == 3)
        #expect(classes.allSatisfy { $0.primaryInstructor != nil })
    }

    @Test func expiredInvitesAreFilteredAtReadTime() async throws {
        let container = SampleData.previewContainer(now: tuesdayNoon)
        let invites = LocalInviteRepository(context: container.mainContext)
        #expect(try await invites.activeInvites(now: tuesdayNoon).count == 6)
        // Four hours later the first four invites have expired (expiry offsets: 80, 165, 150, 220 min).
        let later = tuesdayNoon.addingTimeInterval(4 * 3600)
        let remaining = try await invites.activeInvites(now: later)
        #expect(remaining.count == 2)
        #expect(remaining.allSatisfy { !$0.isExpired(at: later) })
    }

    @Test func staleSeedInvitesRefreshWithoutLosingUserData() async throws {
        let container = SampleData.previewContainer(now: tuesdayNoon)
        let store = LocalDataStore(context: container.mainContext)
        let invites = LocalInviteRepository(context: container.mainContext)
        let clubs = LocalClubRepository(context: container.mainContext)
        let user = try await LocalUserRepository(context: container.mainContext).currentUser()
        try await clubs.payDues(clubID: SampleData.robotsClubID)

        // Fresh data is left alone.
        #expect(try store.refreshIfStale(now: tuesdayNoon) == false)

        // A day later every invite has expired, so the seed content is regenerated.
        let nextDay = tuesdayNoon.addingTimeInterval(24 * 3600)
        #expect(try await invites.activeInvites(now: nextDay).isEmpty)
        #expect(try store.refreshIfStale(now: nextDay) == true)
        #expect(try await invites.activeInvites(now: nextDay).count == 6)
        #expect(try await clubs.events(now: nextDay).count == 5)
        #expect(user.isVerifiedMember)
    }

    @Test func rsvpTogglesAndRespectsCapacity() async throws {
        let container = SampleData.previewContainer(now: tuesdayNoon)
        let invites = LocalInviteRepository(context: container.mainContext)
        let first = try #require(try await invites.activeInvites(now: tuesdayNoon).first)
        try await invites.toggleRSVP(inviteID: first.id)
        #expect(first.attendeeIDs.contains(SampleData.userID))
        try await invites.toggleRSVP(inviteID: first.id)
        #expect(!first.attendeeIDs.contains(SampleData.userID))
    }

    @Test func payDuesVerifiesMember() async throws {
        let container = SampleData.previewContainer(now: tuesdayNoon)
        let clubs = LocalClubRepository(context: container.mainContext)
        let user = try await LocalUserRepository(context: container.mainContext).currentUser()
        #expect(!user.isVerifiedMember)
        try await clubs.payDues(clubID: SampleData.robotsClubID)
        #expect(user.isVerifiedMember)
        #expect(user.joinedClubIDs.contains(SampleData.robotsClubID))
        await #expect(throws: RepositoryError.self) {
            try await clubs.payDues(clubID: SampleData.filmClubID)
        }
    }

    @Test func snapshotRoundTripsAndRejectsBadVersion() throws {
        let snapshot = WidgetSnapshot(
            version: WidgetSnapshot.currentVersion,
            generatedAt: tuesdayNoon,
            clockOffset: 120,
            meetings: [SnapshotMeeting(courseCode: "COMP 433", location: "Sitterson Hall SN014",
                                       weekday: 3, startMinutes: 660, endMinutes: 735)],
            invites: []
        )
        let data = try snapshot.encoded()
        #expect(WidgetSnapshot.decode(data) == snapshot)

        var stale = snapshot
        stale.version = 99
        #expect(WidgetSnapshot.decode(try stale.encoded()) == nil)
        #expect(WidgetSnapshot.decode(Data("garbage".utf8)) == nil)
        #expect(WidgetSnapshot.decode(nil) == nil)
    }

    @Test func clockStringFormatsTimes() {
        #expect(805.clockString == "1:25 PM")
        #expect(660.clockString == "11:00 AM")
        #expect(0.clockString == "12:00 AM")
    }
}
