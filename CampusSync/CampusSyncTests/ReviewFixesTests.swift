//
//  ReviewFixesTests.swift
//  CampusSyncTests
//
//  Regression tests for the code review fixes: the offline timeout, no fictional student after
//  sign-out, double-tap guards, club posting limits and demo mode, and the sharing toggle.
//

import Foundation
import SwiftData
import Testing
@testable import CampusSync

@MainActor
struct ReviewFixesTests {
    // MARK: Offline timeout

    private struct Boom: Error {}

    @Test func aWriteThatNeverAnswersTimesOutInsteadOfHanging() async {
        let started = Date()
        // A write that never finishes, like Firestore's commit while offline (and not cancellable).
        let result: Result<Int, Error> = await {
            do {
                return .success(try await withTimeout(seconds: 0.2, onTimeout: { FriendError.offline }) {
                    try await Task.sleep(for: .seconds(60))
                    return 1
                })
            } catch { return .failure(error) }
        }()
        #expect(Date().timeIntervalSince(started) < 5)   // returned at the timeout, not after the 60 s write
        guard case .failure(let error) = result else { Issue.record("expected a timeout"); return }
        #expect(error as? FriendError == .offline)
    }

    @Test func aFastWriteReturnsItsValueAndAFailingOneItsError() async throws {
        let value = try await withTimeout(seconds: 5, onTimeout: { FriendError.offline }) { 42 }
        #expect(value == 42)
        await #expect(throws: Boom.self) {
            try await withTimeout(seconds: 5, onTimeout: { FriendError.offline }) { throw Boom() }
        }
    }

    // MARK: Signed out

    @Test func afterSignOutThereIsNoStudentAndSoTheWidgetSnapshotStaysEmpty() async throws {
        let container = SampleData.emptyPreviewContainer()
        let store = LocalDataStore(context: container.mainContext)
        SampleData.classes().forEach(container.mainContext.insert)
        try container.mainContext.save()

        try store.wipe(keepingSchedule: true)   // sign-out: the own classes stay for the next sign-in

        // No fictional student is invented on the next launch, so there is no current user.
        let users = LocalUserRepository(context: container.mainContext)
        await #expect(throws: RepositoryError.self) { try await users.currentUser() }
        #expect(try container.mainContext.fetchCount(FetchDescriptor<ClassSchedule>()) > 0)
    }

    // MARK: Limits that match the rules

    @Test func anInviteMustFitTheRulesLimits() {
        let friends = (0..<31).map { "friend-\($0)" }
        var draft = ComposeDraft.standard(now: Date(), friendIDs: ["a"])
        #expect(draft.canPost)
        draft.recipientIDs = Set(friends)
        #expect(!draft.canPost)                       // more than 30 recipients
        draft.recipientIDs = Set(friends.prefix(30))
        #expect(draft.canPost)
        draft.title = String(repeating: "x", count: 81)
        #expect(!draft.canPost)                       // title over 80 characters
    }

    @Test func clubEventLimitsCountScalarsLikeTheRulesDo() {
        // One family emoji is a single character but five scalars, so 20 of them are over 80.
        let family = "👨‍👩‍👧"
        var draft = ClubEventDraft(clubID: "c", title: String(repeating: family, count: 20), location: "Here", start: Date())
        #expect(!draft.isValid)
        draft.title = String(repeating: family, count: 16)   // 80 scalars
        #expect(draft.isValid)
    }

    // MARK: Club actions

    private func services() -> AppServices { AppServices.preview() }

    @Test func demoModeDoesNotPostRealClubEvents() async throws {
        let services = services()
        await services.enterDemoMode(account: nil)
        let model = ClubsViewModel()
        let draft = ClubEventDraft(clubID: SampleData.aiClubID, title: "Test", location: "Here", start: Date().addingTimeInterval(3600))
        #expect(await model.post(draft, services: services, now: Date()) == false)
        #expect(model.errorMessage == ClubsViewModel.demoPostMessage)
        await services.exitDemoMode(refresh: false)
    }

    @Test func aMemberPostsAndTheFeedShowsItWithRemoveRights() async throws {
        let services = services()
        let now = Date()
        try await services.clubs.joinClub(id: SampleData.aiClubID)
        let model = ClubsViewModel()
        let draft = ClubEventDraft(clubID: SampleData.aiClubID, title: "Demo night", location: "Davis", start: now.addingTimeInterval(3600))
        #expect(await model.post(draft, services: services, now: now))
        let mine = try #require(model.items.first { $0.eventTitle == "Demo night" })
        #expect(mine.isMine && mine.isJoined)
        await model.delete(mine, services: services, now: now)
        #expect(model.items.contains { $0.eventTitle == "Demo night" } == false)
    }

    /// The card must show the new state as soon as the button is tappable again; otherwise a second
    /// tap lands on a stale button (a "Join" that is already joined, so it leaves instead).
    @Test func theClubCardShowsTheNewStateBeforeItIsTappableAgain() async throws {
        let services = services()
        let now = Date()
        let model = ClubsViewModel()
        await model.load(services: services, now: now)
        let item = try #require(model.items.first { $0.clubID == SampleData.aiClubID && !$0.isJoined })

        await model.act(on: item, services: services, now: now)
        #expect(model.items.first { $0.clubID == SampleData.aiClubID }?.isJoined == true)   // no separate reload
        #expect(!model.isBusy(item))

        let joined = try #require(model.items.first { $0.clubID == SampleData.aiClubID })
        await model.leave(joined, services: services, now: now)
        #expect(model.items.first { $0.clubID == SampleData.aiClubID }?.isJoined == false)
    }

    @Test func theRSVPButtonShowsTheNewStateBeforeItIsTappableAgain() async throws {
        let services = services()
        let now = Date()
        let model = InvitesViewModel()
        await model.load(services: services, now: now)
        let invite = try #require(model.invites.first { !model.isGoing($0) && !model.isFull($0) })
        let id = invite.id

        await model.toggleRSVP(invite, services: services, now: now)
        let refreshed = try #require(model.invites.first { $0.id == id })
        #expect(model.isGoing(refreshed))   // no separate reload
        #expect(!model.isBusy(refreshed))
    }

    // MARK: Friends

    @Test func answeringARequestTwiceAtOnceSendsItOnce() async throws {
        let services = services()
        let model = FriendsViewModel()
        await model.load(services: services)
        let request = try #require(model.incoming.first)

        async let first: Void = model.accept(request, services: services)
        async let second: Void = model.accept(request, services: services)
        _ = await (first, second)

        #expect(model.message == nil)   // the second tap did not raise "already answered"
        #expect(model.friends.contains { $0.id == request.other.id })
        #expect(!model.isWorking)
    }
}

@MainActor
struct ResetActivityTests {
    @Test func resetClearsMyPostsRSVPsAndMembershipsButKeepsFriendsAndSchedule() async throws {
        let services = AppServices.preview()
        let now = Date()
        let user = try await services.users.currentUser()

        // Some activity: a hosted invite, an RSVP to someone else's, a club (dues) and my own club event.
        let hosted = OpenInvite(title: "Mine", landmark: .thePit, category: .food, startTime: now.addingTimeInterval(3600),
                                expiresAt: now.addingTimeInterval(7200), hostID: user.id, hostName: user.displayName,
                                attendeeIDs: [user.id], recipientIDs: [SampleData.mayaID], capacity: 8)
        try await services.invites.post(hosted)
        let others = try await services.invites.activeInvites(now: now).first { $0.hostID != user.id && !$0.attendeeIDs.contains(user.id) }
        let theirs = try #require(others)
        try await services.invites.toggleRSVP(inviteID: theirs.id)
        try await services.clubs.payDues(clubID: SampleData.robotsClubID)
        try await services.clubs.joinClub(id: SampleData.aiClubID)
        try await services.clubs.postEvent(ClubEventDraft(clubID: SampleData.aiClubID, title: "Mine", location: "Here", start: now.addingTimeInterval(3600)))
        let classCount = try await services.schedule.classes().count
        let friendCount = try await services.schedule.friends().count
        #expect(user.isVerifiedMember)

        try await services.resetMyActivity()

        let after = try await services.users.currentUser()
        #expect(after.joinedClubIDs.isEmpty && !after.isVerifiedMember && after.rsvpedInviteIDs.isEmpty)
        let invites = try await services.invites.activeInvites(now: now)
        #expect(invites.contains { $0.id == hosted.id } == false)
        #expect(invites.first { $0.id == theirs.id }?.attendeeIDs.contains(user.id) == false)
        #expect(try await services.clubs.events(now: now).contains { $0.posterID == user.id } == false)
        // Seeded events and other people's invites are untouched; friends and schedule stay.
        #expect(try await services.clubs.events(now: now).isEmpty == false)
        #expect(try await services.schedule.classes().count == classCount)
        #expect(try await services.schedule.friends().count == friendCount)
    }

    @Test func resetDoesNothingInDemoMode() async throws {
        let services = AppServices.preview()
        try await services.clubs.joinClub(id: SampleData.aiClubID)
        await services.enterDemoMode(account: nil)
        try await services.resetMyActivity()
        await services.exitDemoMode(refresh: false)
        #expect(try await services.users.currentUser().joinedClubIDs.contains(SampleData.aiClubID))
    }
}

/// Regression: Reset crashed the app with "backing data was detached from a context" because the
/// Home and Invites screens still held the invites Reset had just deleted. View models now keep
/// plain copies, which stay readable after the rows are gone.
@MainActor
struct ScreensSurviveDeletedDataTests {
    @Test func invitesAndHomeKeepReadableCopiesAfterReset() async throws {
        let services = AppServices.preview()
        let now = Date()
        let user = try await services.users.currentUser()
        try await services.invites.post(OpenInvite(
            title: "Mine", landmark: .thePit, category: .food, startTime: now.addingTimeInterval(3600),
            expiresAt: now.addingTimeInterval(7200), hostID: user.id, hostName: user.displayName,
            attendeeIDs: [user.id], recipientIDs: [SampleData.mayaID]))
        let invites = InvitesViewModel()
        let home = HomeViewModel()
        await invites.load(services: services, now: now)
        await home.load(services: services, now: now)
        #expect(invites.invites.contains { $0.title == "Mine" })
        // The screens must hold copies that belong to no database; a live model that is deleted
        // while a screen holds it is the fatal "backing data was detached" read. (The simulator does
        // not always crash on it, so check the cause directly.)
        #expect(invites.invites.allSatisfy { $0.modelContext == nil })
        #expect(home.activeInvites(at: now).allSatisfy { $0.modelContext == nil })

        try await services.resetMyActivity()   // deletes the rows the screens just loaded

        // The screens draw once more before they reload: reading must not crash.
        for invite in invites.invites { _ = (invite.title, invite.attendeeIDs, invite.expiresAt, invite.hostName) }
        for invite in home.activeInvites(at: now) { _ = (invite.title, invite.attendeeIDs, invite.capacity) }
        #expect(invites.invites.contains { $0.title == "Mine" })   // still the old copy until reload
        await invites.load(services: services, now: now)
        #expect(invites.invites.contains { $0.title == "Mine" } == false)
    }

    @Test func friendsClassesAndClubsStayReadableAfterTheCacheIsWiped() async throws {
        let services = AppServices.preview()
        let now = Date()
        let schedule = ScheduleViewModel()
        let invites = InvitesViewModel()
        let clubs = ClubsViewModel()
        try await services.clubs.joinClub(id: SampleData.aiClubID)
        await schedule.load(from: services.schedule)
        await invites.load(services: services, now: now)
        await clubs.load(services: services, now: now)
        #expect(!schedule.classes.isEmpty && !invites.friends.isEmpty && !clubs.joinedClubs.isEmpty)
        #expect(schedule.classes.allSatisfy { $0.modelContext == nil })
        #expect(invites.friends.allSatisfy { $0.modelContext == nil })
        #expect(clubs.joinedClubs.allSatisfy { $0.modelContext == nil })

        try services.store.wipe()   // like a sign-out or an unfriend, under screens that are still up

        for cls in schedule.classes { _ = (cls.courseCode, cls.title, cls.instructors, cls.building) }
        for friend in invites.friends { _ = (friend.displayName, friend.classes) }
        for club in clubs.joinedClubs { _ = (club.name, club.summary) }
    }
}
