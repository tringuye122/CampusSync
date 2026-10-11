//
//  HomeDashboardView.swift
//  CampusSync
//
//  One scroll under the profile header: the FREE NOW hero, a collapsible Today card, friends who
//  are free right now (tap one to see both schedules), and a carousel of active friend invites.
//

import SwiftUI

struct HomeDashboardView: View {
    @Environment(AppServices.self) private var services
    @Environment(AppClock.self) private var clock
    @Environment(AppRouter.self) private var router
    @State private var viewModel = HomeViewModel()

    var body: some View {
        // One per-minute tick drives everything time-based (hero, Today, who is free now, invite
        // countdowns), always against AppClock.
        TimelineView(.everyMinute) { _ in
            let now = clock.now
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    LiveStatusBanner(meetings: viewModel.meetings)
                        .padding(.horizontal, 16)

                    TodayCard(
                        classes: viewModel.todayMeetings(at: now),
                        next: viewModel.nextClassToday(at: now))
                        .padding(.horizontal, 16)

                    friendsFreeNowSection(now: now)
                    invitesSection(now: now)
                }
                .padding(.vertical, 16)
            }
            // Friends' schedules are fetched, not listened to, so pull down to see who is free now.
            .refreshable { await services.sync.refreshAll() }
        }
        .withAppHeader()
        .onAppear { Task { await viewModel.load(services: services, now: clock.now) } }
        .onChange(of: services.sync.changeCount) { Task { await viewModel.load(services: services, now: clock.now) } }
        .onChange(of: services.dataVersion) { Task { await viewModel.load(services: services, now: clock.now) } }
    }

    // MARK: Friends free now

    private func friendsFreeNowSection(now: Date) -> some View {
        let entries = viewModel.friendStatuses(at: now)
        return VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Friends free now")
            if entries.isEmpty {
                Text(viewModel.friends.isEmpty
                     ? "Add friends in Schedule > Friends, then you'll see who is free here."
                     : "No friends to show yet.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                    .cardStyle()
                    .padding(.horizontal, 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(entries) { entry in
                            Button { router.showFriendOverlap(friendID: entry.friendID) } label: {
                                FriendFreeNowCard(status: entry)
                            }
                            .buttonStyle(.plain)
                            .frame(width: FriendFreeNowCard.width)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    // MARK: Invites

    private func invitesSection(now: Date) -> some View {
        let invites = viewModel.activeInvites(at: now)
        return VStack(alignment: .leading, spacing: 12) {
            sectionTitle("Invites")
            if invites.isEmpty {
                Text("No active plans right now. Post one from the Invites tab.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
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
                            .frame(width: 320)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.title2.bold())
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 16)
            .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    // Tuesday 12:15 PM, so the demo user is free and Maya and Sam share the gap.
    let clock = AppClock()
    let calendar = Calendar.current
    clock.setOverride(to: calendar.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 12, minute: 15))!)
    let backend = MockAuthBackend(signedInEmail: "justin@unc.edu")
    backend.seed(email: "justin@unc.edu", password: "password1", displayName: "Justin Nguyen", handle: "justin")
    let auth = AuthService(backend: backend, defaults: UserDefaults(suiteName: "preview-home")!)
    return HomeDashboardView()
        .environment(AppServices.preview(now: clock.now))
        .environment(clock)
        .environment(AppRouter())
        .environment(auth)
        .task { await auth.refresh() }
}
