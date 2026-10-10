//
//  SyncTests.swift
//  CampusSyncTests
//
//  The parts of Phase 8 sync that need no network: Firestore document coding (whose
//  field names must match firestore.rules) and tying the cache to an account.
//  The listeners and repositories are covered end to end in FirebaseIntegrationTests.
//

import FirebaseFirestore
import Foundation
import SwiftData
import Testing
@testable import CampusSync

// Serialized: these tests share the global schedule-owner setting.
@MainActor
@Suite(.serialized)
struct SyncTests {
    @Test func inviteRoundTripsThroughItsDocument() throws {
        let invite = OpenInvite(
            id: "i1", title: "Lunch", landmark: .thePit, category: .food,
            startTime: Date(timeIntervalSince1970: 1_800_000_000), expiresAt: Date(timeIntervalSince1970: 1_800_003_600),
            hostID: "ann", hostName: "Ann", attendeeIDs: ["ann"], recipientIDs: ["bob", "cy"], capacity: 6)
        let data = FirestoreCoding.data(for: invite)
        // The rules require exactly these keys.
        #expect(Set(data.keys) == [
            "title", "landmark", "category", "startTime", "expiresAt",
            "hostID", "hostName", "attendeeIDs", "recipientIDs", "capacity",
        ])
        let decoded = try #require(FirestoreCoding.invite(id: "i1", data: data))
        #expect(decoded.title == "Lunch")
        #expect(decoded.landmark == .thePit && decoded.category == .food)
        #expect(decoded.expiresAt == invite.expiresAt)
        #expect(decoded.recipientIDs == ["bob", "cy"] && decoded.capacity == 6)
    }

    @Test func malformedInviteDocumentsAreSkippedNotFatal() {
        #expect(FirestoreCoding.invite(id: "x", data: ["title": "No dates"]) == nil)
        #expect(FirestoreCoding.invite(id: "x", data: [:]) == nil)
    }

    /// Privacy: a shared meeting carries times and a building, and nothing that identifies the
    /// course title, instructor, student name or ID. The rules reject any other key as well.
    @Test func sharedMeetingHoldsTimesAndBuildingOnly() throws {
        let comp523 = try #require(SampleData.classes().first { $0.courseCode == "COMP 523" })
        let data = FirestoreCoding.data(for: comp523.meeting)
        #expect(Set(data.keys) == ["courseCode", "weekdays", "startMinutes", "endMinutes", "building"])
        let text = String(describing: data)
        #expect(!text.contains("Software Engineering"))   // the title
        #expect(!text.contains("Stotts"))                  // an instructor
        let decoded = try #require(FirestoreCoding.meeting(data: data))
        #expect(decoded == comp523.meeting)
    }

    @Test func badMeetingDocumentsAreSkipped() {
        #expect(FirestoreCoding.meeting(data: ["courseCode": "X"]) == nil)
        #expect(FirestoreCoding.meeting(data: [
            "courseCode": "X", "weekdays": [9], "startMinutes": 1, "endMinutes": 2, "building": "B",
        ]) == nil)   // no valid weekday
    }

    @Test func clubAndEventDocumentsDecode() throws {
        let club = try #require(FirestoreCoding.club(id: "c1", data: [
            "name": "Chess", "summary": "Games", "symbol": "crown.fill", "access": "duesRequired", "duesAmount": 15,
        ]))
        #expect(club.access == .duesRequired && club.duesAmount == 15)
        #expect(FirestoreCoding.club(id: "c2", data: ["name": "Bad", "access": "nonsense"]) == nil)

        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let event = try #require(FirestoreCoding.event(id: "e1", clubID: "c1", clubName: "Chess", data: [
            "title": "Open play", "startTime": Timestamp(date: start), "access": "public",
        ]))
        #expect(event.clubID == "c1" && event.startTime == start && event.access == .public)
    }

    // MARK: Account cache

    private func store() throws -> (LocalDataStore, ModelContext) {
        ScheduleOwner.uid = nil   // each test starts as a fresh install
        let container = SampleData.previewContainer()   // seeded demo data
        let context = container.mainContext
        return (LocalDataStore(context: context), context)
    }

    private let account = UserAccount(uid: "real-uid", email: "pat@unc.edu", displayName: "Pat Example", handle: "pat")

    @Test func adoptingAnAccountReplacesTheSeededDemoData() throws {
        let (store, context) = try store()
        #expect(try context.fetchCount(FetchDescriptor<ClassSchedule>()) > 0)

        #expect(try store.adoptAccount(account))   // reset
        let users = try context.fetch(FetchDescriptor<UserProfile>())
        #expect(users.map(\.id) == ["real-uid"])
        #expect(users.first?.handle == "pat")
        #expect(try context.fetchCount(FetchDescriptor<ClassSchedule>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<OpenInvite>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<FriendProfile>()) == 0)
    }

    @Test func adoptingTheSameAccountAgainKeepsTheCache() throws {
        let (store, context) = try store()
        try store.adoptAccount(account)
        context.insert(ClassSchedule(
            courseCode: "COMP 1", title: "T", section: "001", units: 3, weekdays: [.mon],
            startMinutes: 600, endMinutes: 660, building: "B", room: "1",
            startDate: Date(), endDate: Date(), instructors: []))
        try context.save()

        #expect(try store.adoptAccount(account) == false)   // same uid: nothing is reset
        #expect(try context.fetchCount(FetchDescriptor<ClassSchedule>()) == 1)
    }

    @Test func aDifferentAccountNeverSeesThePreviousStudentsData() throws {
        let (store, context) = try store()
        try store.adoptAccount(account)
        context.insert(FriendProfile(id: "friend", displayName: "Friend", classes: []))
        try context.save()

        try store.adoptAccount(UserAccount(uid: "other", email: "o@unc.edu", displayName: "Other", handle: "other"))
        #expect(try context.fetchCount(FetchDescriptor<FriendProfile>()) == 0)
        #expect(try context.fetch(FetchDescriptor<UserProfile>()).map(\.id) == ["other"])
    }

    @Test func wipeEmptiesEverything() throws {
        let (store, context) = try store()
        try store.wipe()
        #expect(try context.fetchCount(FetchDescriptor<UserProfile>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Club>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<ClubEvent>()) == 0)
    }

    @Test func sharingCanBeSwitchedOffThroughTheRepository() async throws {
        let original = ScheduleSharingSetting.isEnabled
        defer { ScheduleSharingSetting.setEnabled(original) }
        let services = AppServices.preview()   // local repositories: no Firestore involved
        try await services.schedule.setSharesScheduleWithFriends(false)
        #expect(!services.schedule.sharesScheduleWithFriends)
        try await services.schedule.setSharesScheduleWithFriends(true)
        #expect(services.schedule.sharesScheduleWithFriends)
    }

    // MARK: Review fixes

    /// Course titles and instructors exist only on this device, so sign-out keeps the student's
    /// own classes (for the same account only) while clearing everything that came from the server.
    @Test func signOutKeepsOwnClassesForTheSameAccountButDropsServerData() throws {
        let originalOwner = ScheduleOwner.uid
        defer { ScheduleOwner.uid = originalOwner }
        let (store, context) = try store()
        ScheduleOwner.uid = nil
        try store.adoptAccount(account)
        SampleData.classes().forEach(context.insert)
        context.insert(FriendProfile(id: "friend", displayName: "Friend", classes: []))
        try context.save()
        let classCount = try context.fetchCount(FetchDescriptor<ClassSchedule>())

        try store.wipe(keepingSchedule: true)   // what sign-out does
        #expect(try context.fetchCount(FetchDescriptor<ClassSchedule>()) == classCount)
        #expect(try context.fetchCount(FetchDescriptor<FriendProfile>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<UserProfile>()) == 0)

        // Same student signs back in: their classes are still there.
        try store.adoptAccount(account)
        #expect(try context.fetchCount(FetchDescriptor<ClassSchedule>()) == classCount)

        // A different student on the same phone never inherits them.
        try store.wipe(keepingSchedule: true)
        try store.adoptAccount(UserAccount(uid: "other", email: "o@unc.edu", displayName: "Other", handle: "other"))
        #expect(try context.fetchCount(FetchDescriptor<ClassSchedule>()) == 0)
    }

    @Test func staleSeedRefreshNeverTouchesARealAccountsCache() throws {
        let originalOwner = ScheduleOwner.uid
        defer { ScheduleOwner.uid = originalOwner }
        let (store, context) = try store()
        try store.adoptAccount(account)   // real account, no invites (normal)
        context.insert(ClubEvent(
            clubID: "c1", clubName: "Real Club", title: "Real event", details: "", location: "",
            startTime: Date().addingTimeInterval(3600), access: .public))
        try context.save()

        #expect(try store.refreshIfStale(now: Date()) == false)
        let events = try context.fetch(FetchDescriptor<ClubEvent>())
        #expect(events.map(\.title) == ["Real event"])        // not replaced by fictional events
        #expect(try context.fetchCount(FetchDescriptor<OpenInvite>()) == 0)
    }

    @Test func publishableMeetingsDropWhatTheRulesWouldReject() {
        func cls(_ code: String, _ days: [Weekday], _ start: Int, _ end: Int, _ building: String) -> ClassSchedule {
            ClassSchedule(
                courseCode: code, title: "T", section: "001", units: 3, weekdays: days,
                startMinutes: start, endMinutes: end, building: building, room: "1",
                startDate: Date(), endDate: Date(), instructors: [])
        }
        let classes = [
            cls("COMP 100", [.mon], 600, 660, "Sitterson Hall"),            // fine
            cls("NO DAYS", [], 600, 660, "B"),                              // TBA day: dropped
            cls("BACKWARDS", [.tue], 700, 650, "B"),                        // ends before it starts: dropped
            cls("PAST MIDNIGHT", [.wed], 1400, 1500, "B"),                  // dropped
            cls("A VERY LONG COURSE CODE", [.thu], 600, 660, String(repeating: "x", count: 90)),   // trimmed, kept
        ]
        let published = ScheduleSharing.publishable(classes)
        #expect(published.map(\.courseCode) == ["COMP 100", "A VERY LONG "])
        #expect(published.allSatisfy { $0.courseCode.count <= 12 && $0.building.count <= 60 })
    }

    @Test func widgetSnapshotIsEmptyOnceNobodyIsSignedIn() async throws {
        let services = AppServices.preview()   // seeded: classes and invites exist
        try await services.store.wipe()        // signed out: no cached student
        await services.syncWidget()
        // Reads the App Group file (empty if the container is unavailable in the test host);
        // either way it must hold nothing from the previous student.
        let snapshot = WidgetSnapshot.load()
        #expect(snapshot.meetings.isEmpty)
        #expect(snapshot.invites.isEmpty)
    }
}
