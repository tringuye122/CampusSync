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
        retaining container: ModelContainer? = nil
    ) {
        self.clock = clock
        retainedContainer = container
        users = LocalUserRepository(context: context)
        schedule = LocalScheduleRepository(context: context, ratings: ratings)
        invites = LocalInviteRepository(context: context)
        clubs = LocalClubRepository(context: context)
        store = LocalDataStore(context: context)
    }

    /// Rewrites the widget snapshot from current local data and reloads widget timelines.
    /// Call after any local write (new invite, RSVP, import) and when the app foregrounds.
    func syncWidget() async {
        let now = clock.now
        guard let classes = try? await schedule.classes(),
              let active = try? await invites.activeInvites(now: now)
        else { return }
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
    static func preview(now: Date = Date()) -> AppServices {
        let container = SampleData.previewContainer(now: now)
        return AppServices(
            context: container.mainContext, ratings: PreviewRatingProvider(), retaining: container)
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
