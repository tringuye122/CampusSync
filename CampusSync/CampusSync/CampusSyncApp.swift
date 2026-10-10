//
//  CampusSyncApp.swift
//  CampusSync
//
//  Created by Tri Nguyen on 10/10/26.
//

import SwiftData
import SwiftUI

@main
struct CampusSyncApp: App {
    private let container: ModelContainer
    @State private var clock: AppClock
    @State private var services: AppServices

    init() {
        let container: ModelContainer
        do {
            container = try ModelContainer(for: Schema(AppSchema.models))
        } catch {
            fatalError("Could not create the SwiftData container: \(error)")
        }

        let clock = AppClock()
        let services = AppServices(context: container.mainContext)
        // Seed only when the store is empty. Offline, no network involved.
        try? services.store.seedIfNeeded(now: clock.now)
        // Seed invites are timed relative to first launch, so refresh them if they have all expired.
        try? services.store.refreshIfStale(now: clock.now)

        self.container = container
        _clock = State(initialValue: clock)
        _services = State(initialValue: services)
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(clock)
                .environment(services)
        }
        .modelContainer(container)
    }
}
