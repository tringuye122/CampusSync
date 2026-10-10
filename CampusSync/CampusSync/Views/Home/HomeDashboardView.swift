//
//  HomeDashboardView.swift
//  CampusSync
//
//  Live status banner plus a horizontal carousel of active friend invites,
//  soonest first.
//

import SwiftUI

struct HomeDashboardView: View {
    @Environment(AppServices.self) private var services
    @Environment(AppClock.self) private var clock
    @State private var viewModel = HomeViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    LiveStatusBanner(meetings: viewModel.meetings)
                        .padding(.horizontal, 16)

                    invitesSection
                }
                .padding(.vertical, 12)
            }
            .background(Theme.screenBackground)
            .navigationTitle("Home")
            .onAppear { Task { await viewModel.load(services: services, now: clock.now) } }
        }
    }

    private var invitesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Friend Invites")
                .font(.title3.bold())
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 16)

            TimelineView(.everyMinute) { _ in
                let now = clock.now
                let invites = viewModel.activeInvites(at: now)
                if invites.isEmpty {
                    Text("No active plans right now. Post one from the Invites tab.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .cardStyle()
                        .padding(.horizontal, 16)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(invites) { invite in
                                OpenInviteCardView(
                                    invite: invite,
                                    now: now,
                                    isGoing: viewModel.isGoing(invite),
                                    isFull: viewModel.isFull(invite),
                                    isHost: invite.hostID == viewModel.userID
                                ) {
                                    Task { await viewModel.toggleRSVP(invite, services: services) }
                                }
                                .frame(width: 300)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
        }
    }
}

#Preview {
    HomeDashboardView()
        .environment(AppServices.preview())
        .environment(AppClock())
}
