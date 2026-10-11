//
//  AppServices.swift
//  CampusSync
//
//  Composition root: builds the repositories once from a ModelContext and hands
//  them to ViewModels through the SwiftUI environment. Swapping in Firestore
//  later means changing the initializer here, not any view.
//

import Foundation
import Observation
import SwiftData
import WidgetKit

@Observable
final class AppServices {
    // Users, schedule, invites and friends are swapped for demo data in demo mode; clubs stay live.
    private(set) var users: UserRepository
    private(set) var schedule: ScheduleRepository
    private(set) var invites: InviteRepository
    let clubs: ClubRepository
    private(set) var friends: FriendRepository
    /// Firestore listeners that keep the local cache current. Idle until `start(account:)`.
    let sync: SyncCoordinator
    /// Bumped after every local write (import, post, RSVP, join), so shared UI like the header
    /// can reload. Server-driven changes are signalled by `sync.changeCount` instead.
    private(set) var dataVersion = 0
    /// Seed and reset hooks for the dev menu.
    let store: LocalDataStore
    /// Keeps an in-memory preview container alive; a ModelContext does not own its container.
    private let retainedContainer: ModelContainer?
    /// The clock the widget snapshot's `clockOffset` is read from.
    let clock: AppClock

    // MARK: Demo mode
    private let liveRepositories: (users: UserRepository, schedule: ScheduleRepository, invites: InviteRepository, friends: FriendRepository)
    private let ratings: ProfessorRatingProvider
    private var demoWorld: DemoWorld?
    /// Demo worlds that have been left, kept alive on purpose. Screens still on display hold demo
    /// models for a moment after the switch, and reading a SwiftData model whose database has been
    /// freed is a fatal error. All are kept for the life of the app: each is a small in-memory
    /// store, and nothing then depends on how quickly the UI rebuilds.
    private var retiredDemoWorlds: [DemoWorld] = []
    private(set) var isDemoMode = false
    /// True while switching between live and demo. Switches never overlap, so a refresh from one
    /// cannot write live data (or a stale widget snapshot) into the other.
    private(set) var isSwitchingDemo = false
    /// Bumped on every switch between live and demo, so the UI rebuilds and reloads from the new data.
    private(set) var demoGeneration = 0
    private static let demoModeKey = "CampusSync.demoMode"
    /// Whether the last session ended in demo mode (restored after sign-in).
    static var wantsDemoMode: Bool { UserDefaults.standard.bool(forKey: demoModeKey) }

    init(
        context: ModelContext,
        clock: AppClock = AppClock(),
        ratings: ProfessorRatingProvider = CachedProfessorRatingProvider.live(),
        friends: FriendRepository = InMemoryFriendRepository.preview(),
        useFirestore: Bool = false,
        retaining container: ModelContainer? = nil
    ) {
        self.clock = clock
        retainedContainer = container
        let localUsers = LocalUserRepository(context: context)
        let localSchedule = LocalScheduleRepository(context: context, ratings: ratings)
        let localInvites = LocalInviteRepository(context: context)
        let localClubs = LocalClubRepository(context: context)
        let coordinator = SyncCoordinator(context: context)   // the club repository refreshes events through it
        let scheduleRepository: ScheduleRepository
        let inviteRepository: InviteRepository
        if useFirestore {
            // Reads stay on the cache; writes also go to Firestore (see FirestoreRepositories.swift).
            scheduleRepository = FirestoreScheduleRepository(local: localSchedule)
            inviteRepository = FirestoreInviteRepository(local: localInvites, users: localUsers)
            clubs = FirestoreClubRepository(local: localClubs, users: localUsers, sync: coordinator)
        } else {
            scheduleRepository = localSchedule
            inviteRepository = localInvites
            clubs = localClubs
        }
        users = localUsers
        schedule = scheduleRepository
        invites = inviteRepository
        store = LocalDataStore(context: context)
        sync = coordinator
        self.friends = friends
        self.ratings = ratings
        liveRepositories = (localUsers, scheduleRepository, inviteRepository, friends)
        sync.onChange = { [weak self] in await self?.syncWidget() }
    }

    /// Live to demo: swaps in the demo friends, schedule and invites, sets the clock to the demo
    /// moment (Tue Oct 13, 12:30 PM) and rewrites the widget. Nothing of the demo data is written to
    /// Firestore. Clubs stay live, so joining or leaving a club in demo mode is a real change; posting
    /// a club event is blocked in demo mode (see ClubsViewModel.canPostEvents).
    func enterDemoMode(account: UserAccount?) async {
        guard !isDemoMode, !isSwitchingDemo else { return }
        isSwitchingDemo = true
        defer { isSwitchingDemo = false }
        let world: DemoWorld
        do {
            world = try DemoWorld(account: account, liveUsers: liveRepositories.users, ratings: ratings)
        } catch {
            debugLog("Could not build the demo data: \(error)")
            return
        }
        demoWorld = world
        users = world.users
        schedule = world.schedule
        invites = world.invites
        friends = world.friends
        clock.setOverride(to: DemoWorld.moment())
        isDemoMode = true
        UserDefaults.standard.set(true, forKey: Self.demoModeKey)
        demoGeneration += 1
        await syncWidget()
    }

    /// Demo to live: stops using the demo data, clears the clock override, and refreshes from
    /// Firestore. The demo world is retired, not freed (see `retiredDemoWorlds`). With
    /// `refresh: false` (sign-out) it only leaves the demo and does not fetch.
    func exitDemoMode(refresh: Bool = true) async {
        UserDefaults.standard.set(false, forKey: Self.demoModeKey)
        guard isDemoMode else { return }
        isSwitchingDemo = true
        defer { isSwitchingDemo = false }
        (users, schedule, invites, friends) = liveRepositories
        if let world = demoWorld { retiredDemoWorlds.append(world) }
        demoWorld = nil
        clock.clearOverride()
        isDemoMode = false
        demoGeneration += 1
        await syncWidget()
        guard refresh else { return }
        // Let the rebuilt screens settle before the refresh rewrites cached friends and events
        // under them.
        try? await Task.sleep(for: .milliseconds(600))
        await sync.refreshAll()
    }

    /// Clears what this student did while trying the app, between live demos: the invites they
    /// posted, their RSVPs, the club events they posted and every club membership. Friends,
    /// the schedule and the account stay. Live data only (demo mode has nothing live to reset).
    func resetMyActivity() async throws {
        guard !isDemoMode else { return }
        // Each step is logged (debug builds), so a stall shows in the console as the last line.
        debugLog("reset: removing my invites and RSVPs")
        try await invites.removeMyInvitesAndRSVPs()
        debugLog("reset: removing my club events and memberships")
        try await clubs.removeMyEventsAndMemberships()
        debugLog("reset: refreshing the widget")
        await syncWidget()
        debugLog("reset: done")
    }

    /// Rewrites the widget snapshot from current local data and reloads widget timelines.
    /// Call after any local write (new invite, RSVP, import) and when the app foregrounds.
    func syncWidget() async {
        dataVersion += 1
        let now = clock.now
        // No cached student means signed out: write an empty snapshot so the previous student's
        // classes and invites never linger on the Home Screen or Lock Screen.
        let user = try? await users.currentUser()
        let signedIn = user != nil
        let classes = signedIn ? ((try? await schedule.classes()) ?? []) : []
        let active = signedIn ? ((try? await invites.activeInvites(now: now)) ?? []) : []
        let friendProfiles = signedIn ? ((try? await schedule.friends()) ?? []) : []
        let snapshot = SnapshotBuilder.make(
            classes: classes, invites: active, friends: friendProfiles,
            userHandle: user?.handle, userName: user?.displayName,
            now: now, clockOffset: clock.offset)
        if snapshot.save() {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// Fetches ratings for every primary instructor in the background so they are cached
    /// before the rating sheet is opened (and keep working offline afterward).
    func warmProfessorRatings() async {
        guard let classes = try? await schedule.classes() else { return }
        var seen = Set<String>()
        for name in classes.compactMap(\.primaryInstructor) where seen.insert(name).inserted {
            _ = await schedule.professorRating(for: name)
        }
    }

    /// A brand-new account: the student only, with no classes, friends, invites or clubs yet.
    /// For previews of the empty states.
    static func previewEmpty() -> AppServices {
        let container = SampleData.emptyPreviewContainer()
        return AppServices(
            context: container.mainContext, ratings: PreviewRatingProvider(),
            friends: InMemoryFriendRepository(me: FriendSummary(id: SampleData.userID, displayName: "Tri Nguyen", handle: "tri")),
            retaining: container)
    }

    /// Seeded in-memory services for previews. Never touches the network: ratings
    /// come from a fixed stub.
    static func preview(now: Date = Date(), friends: FriendRepository = InMemoryFriendRepository.preview()) -> AppServices {
        let container = SampleData.previewContainer(now: now)
        return AppServices(
            context: container.mainContext, ratings: PreviewRatingProvider(), friends: friends,
            retaining: container)
    }
}

/// Fixed ratings for previews and tests, so they never hit the network.
struct PreviewRatingProvider: ProfessorRatingProvider {
    var result: ProfessorRatingLookup = .found(
        ProfessorRating(
            legacyID: 1, firstName: "Alex", lastName: "Example", department: "Computer Science",
            overallRating: 4.1, difficulty: 3.2, wouldTakeAgainPercent: 82, numRatings: 37))

    func rating(for instructor: String) async -> ProfessorRatingLookup { result }
}
