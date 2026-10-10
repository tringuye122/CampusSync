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

    init(context: ModelContext) {
        users = LocalUserRepository(context: context)
        schedule = LocalScheduleRepository(context: context)
        invites = LocalInviteRepository(context: context)
        clubs = LocalClubRepository(context: context)
        store = LocalDataStore(context: context)
    }

    /// Seeded in-memory services for previews.
    static func preview(now: Date = Date()) -> AppServices {
        AppServices(context: SampleData.previewContainer(now: now).mainContext)
    }
}
