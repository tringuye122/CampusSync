//
//  CampusSyncApp.swift
//  CampusSync
//
//  Created by Tri Nguyen on 10/10/26.
//

import FirebaseCore
import SwiftData
import SwiftUI

@main
struct CampusSyncApp: App {
    private let container: ModelContainer
    @State private var clock: AppClock
    @State private var services: AppServices
    @State private var router = AppRouter()
    @State private var auth: AuthService
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Must run before any other Firebase call. Reads the git-ignored GoogleService-Info.plist.
        FirebaseApp.configure()
        // Development only: point at local emulators when FIREBASE_EMULATOR_HOST is set.
        FirebaseEmulator.configureIfRequested()

        let container = Self.makeContainer()

        let clock = AppClock()
        let services = AppServices(
            context: container.mainContext, clock: clock, friends: FirestoreFriendRepository(),
            useFirestore: true)
        // Seed only when the store is empty. Offline, no network involved.
        try? services.store.seedIfNeeded(now: clock.now)
        // Seed invites are timed relative to first launch, so refresh them if they have all expired.
        try? services.store.refreshIfStale(now: clock.now)

        self.container = container
        _auth = State(initialValue: AuthService(backend: FirebaseAuthBackend()))
        _clock = State(initialValue: clock)
        _services = State(initialValue: services)
    }

    /// The SwiftData store is only a cache. Bump this name whenever the schema changes in a
    /// way SwiftData cannot migrate (v2: UUID -> String ids, v3: ClubEvent.endTime, v4: ClubEvent.posterID). The old file is never opened,
    /// so there is nothing to migrate; seeding and Firestore refill the new cache.
    private static let storeName = "CampusSyncCache-v4"

    private static func makeContainer() -> ModelContainer {
        let schema = Schema(AppSchema.models)
        let configuration = ModelConfiguration(storeName, schema: schema)
        // Earlier cache files are never opened again; remove them.
        for legacy in ["default", "CampusSyncCache-v2", "CampusSyncCache-v3"] {
            removeStoreFiles(named: legacy, besides: configuration.url)
        }

        if let container = try? ModelContainer(for: schema, configurations: configuration) {
            return container
        }
        // The new store exists but will not open (corrupt, or a later schema change that was
        // not renamed). It is only a cache, so delete it and start empty.
        debugLog("SwiftData cache could not be opened; rebuilding it.")
        removeStoreFiles(named: storeName, besides: nil, directory: configuration.url.deletingLastPathComponent())
        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            // Disk full or no permission. The store is only a cache, so run from memory rather than crash.
            debugLog("Could not create the SwiftData cache on disk (\(error)); using memory.")
            let memory = ModelConfiguration(isStoredInMemoryOnly: true)
            do {
                return try ModelContainer(for: schema, configurations: memory)
            } catch {
                fatalError("Could not create the SwiftData container: \(error)")
            }
        }
    }

    /// Best-effort delete of `<name>.store` and its -shm/-wal files next to `besides`
    /// (or in `directory`). Failures are logged, not fatal.
    private static func removeStoreFiles(named name: String, besides sibling: URL?, directory: URL? = nil) {
        guard let folder = directory ?? sibling?.deletingLastPathComponent() else { return }
        for suffix in [".store", ".store-shm", ".store-wal"] {
            let url = folder.appendingPathComponent(name + suffix)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                debugLog("Could not remove \(url.lastPathComponent): \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            AuthGateView {
                // Rebuilt whenever demo mode flips, so every screen reloads from the new data.
                MainTabView().id(services.demoGeneration)
            }
            .environment(clock)
            .environment(services)
            .environment(router)
            .environment(auth)
            .onOpenURL { router.open($0) }
            .onChange(of: services.demoGeneration) { router.selectedTab = .home }
            .task { await auth.refresh() }
            // Start Firestore sync once a verified student with a handle is signed in; stop
            // and wipe the cache on sign-out. The app still launches and works with no connection.
            .onChange(of: auth.account, initial: true) { _, account in
                if let account {
                    services.sync.start(account: account)
                    // Demo mode is remembered across launches, so a relaunch stays on the demo.
                    if AppServices.wantsDemoMode, !services.isDemoMode {
                        Task { await services.enterDemoMode(account: account) }
                    }
                } else if case .signedOut = auth.state {
                    // Only on an explicit sign-out. While auth is still loading at launch the
                    // account is nil too, and the offline cache must survive that.
                    services.sync.stop(wipeCache: false)
                    Task {
                        await services.exitDemoMode(refresh: false)
                        // Wipe once the screens have swapped to the signed-out view: deleting rows
                        // that a screen on display still holds is a fatal read.
                        try? await Task.sleep(for: .milliseconds(400))
                        if auth.account == nil { services.sync.stop(wipeCache: true) }   // not if they signed straight back in
                    }
                }
            }
            .task {
                await services.syncWidget()
                // Cache RateMyProfessors ratings now so the rating sheet works offline later.
                await services.warmProfessorRatings()
            }
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            // Refresh the widget whenever the app comes to the foreground.
            if phase == .active {
                Task {
                    await auth.refresh()
                    await services.sync.refreshAll()
                    await services.syncWidget()
                }
            }
        }
    }
}
