//
//  MainTabView.swift
//  CampusSync
//
//  Four-tab shell: Home, Schedule, Friend Invites, Clubs.
//

import SwiftUI

/// Tab identifiers. The widget deep link (Phase 5) selects a tab by these values.
enum AppTab: String, Hashable, CaseIterable {
    case home, schedule, invites, clubs
}

struct MainTabView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.selectedTab) {
            HomeDashboardView()
                .tabItem { Label("Home", systemImage: "house") }
                .tag(AppTab.home)

            ScheduleTabView()
                .tabItem { Label("Schedule", systemImage: "calendar") }
                .tag(AppTab.schedule)

            InvitesTabView()
                .tabItem { Label("Invites", systemImage: "person.badge.plus") }
                .tag(AppTab.invites)

            ClubsTabView()
                .tabItem { Label("Clubs", systemImage: "star.circle") }
                .tag(AppTab.clubs)
        }
        // Selected icon and label use the primary text color (navy in light, near-white in dark;
        // a fixed navy vanished against the dark tab bar). The system fills the selected symbol.
        .tint(Theme.textPrimary)
    }
}

#Preview {
    MainTabView()
        .environment(AppServices.preview())
        .environment(AppClock())
        .environment(AppRouter())
        .environment(AuthService(backend: MockAuthBackend(), defaults: UserDefaults(suiteName: "preview-auth")!))
}
