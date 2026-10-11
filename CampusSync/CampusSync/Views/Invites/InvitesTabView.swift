//
//  InvitesTabView.swift
//  CampusSync
//
//  Friend invites under the profile header: category chips, a flat list soonest first, and a navy
//  "+ Post" button. Expired invites disappear on their own: the list re-filters against the
//  clock every minute.
//

import SwiftUI

struct InvitesTabView: View {
    @Environment(AppServices.self) private var services
    @Environment(AppClock.self) private var clock
    @State private var viewModel = InvitesViewModel()
    @State private var isComposing = false
    @State private var filter = InviteFilter.all

    var body: some View {
        VStack(spacing: 12) {
            FilterChips(values: InviteFilter.allCases, selection: $filter) { $0.title }
                .padding(.top, 12)
            ZStack(alignment: .bottomTrailing) {
                feed
                postButton
            }
        }
        .withAppHeader()
        .onAppear { Task { await viewModel.load(services: services, now: clock.now) } }
        .onChange(of: services.sync.changeCount) { Task { await viewModel.load(services: services, now: clock.now) } }
        .onChange(of: services.dataVersion) { Task { await viewModel.load(services: services, now: clock.now) } }
        .sheet(isPresented: $isComposing) {
            ComposeInviteSheet(
                draft: viewModel.standardDraft(now: clock.now),
                friends: viewModel.friends
            ) { draft in
                Task { await viewModel.post(draft, services: services, now: clock.now) }
            }
            .presentationDetents([.large])
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var feed: some View {
        TimelineView(.everyMinute) { _ in
            let now = clock.now
            let invites = viewModel.filteredInvites(at: now, filter: filter)
            if invites.isEmpty {
                ContentUnavailableView(
                    filter == .all ? "No plans right now" : "No \(filter.title.lowercased()) plans",
                    systemImage: "paperplane",
                    description: Text("Tap + Post to invite your friends to something.").foregroundStyle(Theme.textPrimary)
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 14) {
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
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    // Room so the floating button never covers the last card.
                    .padding(.bottom, 96)
                }
            }
        }
    }

    private var postButton: some View {
        Button {
            isComposing = true
        } label: {
            Label("Post", systemImage: "plus")
                .font(.title3.weight(.heavy))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 28)
                .frame(minHeight: 60)
                .background(Theme.navy, in: Capsule())
                // Navy on the dark-mode cards is nearly invisible, so the button gets an edge.
                .overlay(Capsule().strokeBorder(Color.white.opacity(0.45), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.25), radius: 6, y: 3)
        }
        .padding(20)
        .accessibilityLabel("Post a plan")
    }
}

#Preview {
    InvitesTabView()
        .environment(AppServices.preview())
        .environment(AppClock())
        .environment(AppRouter())
        .environment(AuthService(backend: MockAuthBackend(), defaults: UserDefaults(suiteName: "preview-auth")!))
}

#Preview("New account") {
    InvitesTabView()
        .environment(AppServices.previewEmpty())
        .environment(AppClock())
        .environment(AppRouter())
        .environment(AuthService(backend: MockAuthBackend(), defaults: UserDefaults(suiteName: "preview-auth")!))
}
