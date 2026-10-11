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
