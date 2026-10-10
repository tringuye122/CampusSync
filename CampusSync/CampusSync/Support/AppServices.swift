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

    init(context: ModelContext, clock: AppClock = AppClock(), retaining container: ModelContainer? = nil) {
        self.clock = clock
        retainedContainer = container
        users = LocalUserRepository(context: context)
        schedule = LocalScheduleRepository(context: context)
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

    /// Seeded in-memory services for previews.
    static func preview(now: Date = Date()) -> AppServices {
        let container = SampleData.previewContainer(now: now)
        return AppServices(context: container.mainContext, retaining: container)
    }
}
