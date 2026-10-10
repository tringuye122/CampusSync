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
    let users: UserRepository
    let schedule: ScheduleRepository
    let invites: InviteRepository
    let clubs: ClubRepository
    let friends: FriendRepository
    /// Firestore listeners that keep the local cache current. Idle until `start(account:)`.
    let sync: SyncCoordinator
    /// Seed and reset hooks for the dev menu.
    let store: LocalDataStore
    /// Keeps an in-memory preview container alive; a ModelContext does not own its container.
    private let retainedContainer: ModelContainer?
    /// The clock the widget snapshot's `clockOffset` is read from.
    let clock: AppClock

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
        users = localUsers
        if useFirestore {
            // Reads stay on the cache; writes also go to Firestore (see FirestoreRepositories.swift).
            schedule = FirestoreScheduleRepository(local: localSchedule)
            invites = FirestoreInviteRepository(local: localInvites, users: localUsers)
            clubs = FirestoreClubRepository(local: localClubs, users: localUsers)
        } else {
            schedule = localSchedule
            invites = localInvites
            clubs = localClubs
        }
        store = LocalDataStore(context: context)
        sync = SyncCoordinator(context: context)
        self.friends = friends
        sync.onChange = { [weak self] in await self?.syncWidget() }
    }

    /// Rewrites the widget snapshot from current local data and reloads widget timelines.
    /// Call after any local write (new invite, RSVP, import) and when the app foregrounds.
    func syncWidget() async {
        let now = clock.now
        // No cached student means signed out: write an empty snapshot so the previous student's
        // classes and invites never linger on the Home Screen or Lock Screen.
        let signedIn = (try? await users.currentUser()) != nil
        let classes = signedIn ? ((try? await schedule.classes()) ?? []) : []
        let active = signedIn ? ((try? await invites.activeInvites(now: now)) ?? []) : []
        let snapshot = SnapshotBuilder.make(
            classes: classes, invites: active, now: now, clockOffset: clock.offset)
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
