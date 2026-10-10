//
//  HomeDashboardView.swift
//  CampusSync
//
//  Live status banner (Phase 3). The invites carousel is still a placeholder
//  until Phase 4.
//

import SwiftUI

struct HomeDashboardView: View {
    @Environment(AppServices.self) private var services
    @State private var viewModel = HomeViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    LiveStatusBanner(meetings: viewModel.meetings)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Friend Invites")
                            .font(.title3.bold())
                            .foregroundStyle(Theme.textPrimary)
                        Text("Active plans from friends will show here, soonest first.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .cardStyle()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Theme.screenBackground)
            .navigationTitle("Home")
            .onAppear { Task { await viewModel.load(schedule: services.schedule) } }
        }
    }
}

#Preview {
    HomeDashboardView()
        .environment(AppServices.preview())
        .environment(AppClock())
}
