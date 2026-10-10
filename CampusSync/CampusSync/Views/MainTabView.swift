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
    @State private var selection: AppTab = .home

    var body: some View {
        TabView(selection: $selection) {
            HomeDashboardView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(AppTab.home)

            ScheduleTabView()
                .tabItem { Label("Schedule", systemImage: "calendar") }
                .tag(AppTab.schedule)

            InvitesTabView()
                .tabItem { Label("Invites", systemImage: "paperplane.fill") }
                .tag(AppTab.invites)

            ClubsTabView()
                .tabItem { Label("Clubs", systemImage: "person.3.fill") }
                .tag(AppTab.clubs)
        }
    }
}

#Preview {
    MainTabView()
        .environment(AppServices.preview())
        .environment(AppClock())
}
