//
//  DemoModeTests.swift
//  CampusSyncTests
//
//  Demo mode swaps the data layer onto an in-memory demo world and back. These check what it
//  swaps in, that nothing leaks into live data, and that turning it off restores live.
//

import Foundation
import Testing
@testable import CampusSync

@MainActor
@Suite(.serialized)   // demo mode remembers itself in UserDefaults, which tests share
struct DemoModeTests {
    private let account = UserAccount(uid: "real-uid", email: "pat@unc.edu", displayName: "Pat Example", handle: "pat")

    private func make() -> AppServices {
        UserDefaults.standard.removeObject(forKey: "CampusSync.demoMode")
        return AppServices.preview(now: DemoWorld.moment())
    }

    @Test func enteringDemoSwapsInTheCastTheClockAndTheInvites() async throws {
        let services = make()
        await services.enterDemoMode(account: account)

        #expect(services.isDemoMode)
        #expect(services.clock.isOverridden)
        let friends = try await services.schedule.friends()
        #expect(Set(friends.map(\.displayName)) == ["Maya Patel", "Alex Morgan", "Jordan Lee", "Dee Carter"])
        #expect(try await services.friends.incomingRequests().map(\.other.displayName) == ["Sam Rivera"])
        #expect(try await services.invites.activeInvites(now: DemoWorld.moment()).count == 3)
        let me = try await services.users.currentUser()
        #expect(me.id == "real-uid" && me.displayName == "Pat Example")   // the real account's identity
        #expect(try await services.schedule.classes().count == 4)
    }

    @Test func atTheDemoMomentJordanIsInClassAndTheOthersAreFree() async throws {
        let services = make()
        await services.enterDemoMode(account: account)
        let mine = try await services.schedule.classes().map(\.meeting)
        let friends = try await services.schedule.friends().map { FriendSchedule(id: $0.id, name: $0.displayName, meetings: $0.classes) }

        let statuses = FriendsFreeNow.statuses(mine: mine, friends: friends, now: DemoWorld.moment())
        let byName = Dictionary(uniqueKeysWithValues: statuses.map { ($0.name, $0.state) })
        #expect(byName["Jordan Lee"] == .inClass(until: 13 * 60 + 15))
        for name in ["Maya Patel", "Alex Morgan", "Dee Carter"] {
            if case .mutualFree = byName[name] {} else { Issue.record("\(name) should be free with me at 12:30, got \(String(describing: byName[name]))") }
        }
    }

    @Test func leavingDemoRestoresLiveDataAndTheClock() async throws {
        let services = make()
        let liveFriends = try await services.schedule.friends().map(\.id)
        let generation = services.demoGeneration

        await services.enterDemoMode(account: account)
        await services.exitDemoMode()

        #expect(!services.isDemoMode)
        #expect(!services.clock.isOverridden)
        #expect(try await services.schedule.friends().map(\.id) == liveFriends)
        #expect(services.demoGeneration == generation + 2)   // the UI rebuilt on the way in and out
    }

    @Test func nothingDoneInDemoReachesLiveData() async throws {
        let services = make()
        let liveInvites = try await services.invites.activeInvites(now: DemoWorld.moment()).count

        await services.enterDemoMode(account: account)
        let invite = OpenInvite(
            title: "Demo plan", landmark: .thePit, category: .food,
            startTime: DemoWorld.moment().addingTimeInterval(1800), expiresAt: DemoWorld.moment().addingTimeInterval(5400),
            hostID: "real-uid", hostName: "Pat Example", attendeeIDs: ["real-uid"], recipientIDs: ["demo-maya"])
        try await services.invites.post(invite)
        #expect(try await services.invites.activeInvites(now: DemoWorld.moment()).count == 4)

        await services.exitDemoMode()
        let after = try await services.invites.activeInvites(now: DemoWorld.moment())
        #expect(after.count == liveInvites)
        #expect(!after.contains { $0.title == "Demo plan" })
    }

    @Test func acceptingSamMakesSamAFriendWithAScheduleAndUnfriendingRemovesThem() async throws {
        let services = make()
        await services.enterDemoMode(account: account)
        let request = try #require(try await services.friends.incomingRequests().first)

        try await services.friends.accept(request)
        #expect(try await services.schedule.friends().contains { $0.id == "demo-sam" && !$0.classes.isEmpty })

        try await services.friends.unfriend(request.other)
        #expect(!(try await services.schedule.friends().contains { $0.id == "demo-sam" }))
    }

    @Test func clubMembershipStaysLive() async throws {
        let services = make()
        let live = try await services.users.currentUser()
        live.joinedClubIDs = ["seed-club-ai"]
        live.isVerifiedMember = true

        await services.enterDemoMode(account: account)
        let demoUser = try await services.users.currentUser()
        #expect(demoUser.joinedClubIDs == ["seed-club-ai"] && demoUser.isVerifiedMember)
    }

    @Test func demoModeIsRememberedUntilItIsTurnedOff() async {
        let services = make()
        #expect(!AppServices.wantsDemoMode)
        await services.enterDemoMode(account: account)
        #expect(AppServices.wantsDemoMode)
        await services.exitDemoMode()
        #expect(!AppServices.wantsDemoMode)
    }

    @Test func enteringTwiceDoesNothingTheSecondTime() async {
        let services = make()
        await services.enterDemoMode(account: account)
        let generation = services.demoGeneration
        await services.enterDemoMode(account: account)
        #expect(services.demoGeneration == generation)
    }

    /// Regression: leaving demo mode used to free the demo database at once. Screens still on
    /// display held demo models, and reading any of them after the database was gone is a fatal
    /// error, so the app crashed when demo mode was turned off.
    @Test func demoModelsStayReadableAfterLeavingDemo() async throws {
        let services = make()
        await services.enterDemoMode(account: account)
        let friends = try await services.schedule.friends()
        let invites = try await services.invites.activeInvites(now: DemoWorld.moment())
        let classes = try await services.schedule.classes()

        await services.exitDemoMode()

        // Old screens are still on display for a moment and read these.
        #expect(friends.map(\.displayName).contains("Maya Patel"))
        #expect(invites.first?.title.isEmpty == false)
        #expect(classes.count == 4)
    }

    /// Many quick switches: every demo world stays readable, whenever a slow screen reads it.
    @Test func manyTogglesKeepEveryRetiredWorldReadable() async throws {
        let services = make()
        var held: [[FriendProfile]] = []
        for _ in 0..<6 {
            await services.enterDemoMode(account: account)
            held.append(try await services.schedule.friends())
            await services.exitDemoMode(refresh: false)
        }
        for friends in held { #expect(friends.map(\.displayName).contains("Maya Patel")) }
        #expect(!services.isSwitchingDemo)
    }

    @Test func signOutLeavesDemoWithoutRefreshing() async {
        let services = make()
        await services.enterDemoMode(account: account)
        await services.exitDemoMode(refresh: false)
        #expect(!services.isDemoMode)
        #expect(!AppServices.wantsDemoMode)
    }
}
