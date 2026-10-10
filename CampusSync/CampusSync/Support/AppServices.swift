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

    init(context: ModelContext, retaining container: ModelContainer? = nil) {
        retainedContainer = container
        users = LocalUserRepository(context: context)
        schedule = LocalScheduleRepository(context: context)
        invites = LocalInviteRepository(context: context)
        clubs = LocalClubRepository(context: context)
        store = LocalDataStore(context: context)
    }

    /// Seeded in-memory services for previews.
    static func preview(now: Date = Date()) -> AppServices {
        let container = SampleData.previewContainer(now: now)
        return AppServices(context: container.mainContext, retaining: container)
    }
}
