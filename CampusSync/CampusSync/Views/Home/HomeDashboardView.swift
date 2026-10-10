//
//  HomeDashboardView.swift
//  CampusSync
//
//  Placeholder layout. Phase 3 fills the live status banner (current or next
//  class plus the gap summary); Phase 4 fills the invites carousel.
//

import SwiftUI

struct HomeDashboardView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Live Status", systemImage: "clock.fill")
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                        Text("Your current class or free time will show here.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .cardStyle()

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
        }
    }
}

#Preview {
    HomeDashboardView()
}
