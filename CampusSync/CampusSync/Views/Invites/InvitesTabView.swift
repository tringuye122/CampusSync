//
//  InvitesTabView.swift
//  CampusSync
//
//  Feed of friend invites grouped by time, with a floating "+ Post" button.
//  Expired invites disappear on their own: the list re-filters against the
//  clock every minute.
//

import SwiftUI

struct InvitesTabView: View {
    @Environment(AppServices.self) private var services
    @Environment(AppClock.self) private var clock
    @State private var viewModel = InvitesViewModel()
    @State private var isComposing = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                feed
                postButton
            }
            .background(Theme.screenBackground)
            .navigationTitle("Friend Invites")
            .onAppear { Task { await viewModel.load(services: services, now: clock.now) } }
            .onChange(of: services.sync.changeCount) { Task { await viewModel.load(services: services, now: clock.now) } }
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
    }

    private var feed: some View {
        TimelineView(.everyMinute) { _ in
            let now = clock.now
            let sections = viewModel.sections(at: now)
            if sections.isEmpty {
                ContentUnavailableView(
                    "No plans right now",
                    systemImage: "paperplane",
                    description: Text("Tap + Post to invite your friends to something.")
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(sections) { section in
                            Text(section.kind.title)
                                .font(.title3.bold())
                                .foregroundStyle(Theme.textPrimary)
                                .padding(.top, 4)
                            ForEach(section.invites) { invite in
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
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    // Room so the floating button never covers the last card.
                    .padding(.bottom, 88)
                }
            }
        }
    }

    private var postButton: some View {
        Button {
            isComposing = true
        } label: {
            Label("Post", systemImage: "plus")
                .font(.headline)
                .foregroundStyle(Theme.navy)
                .padding(.horizontal, 20)
                .frame(minHeight: 56)
                .background(Theme.carolinaBlue, in: Capsule())
                .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
        }
        .padding(16)
        .accessibilityLabel("Post a plan")
    }
}

#Preview {
    InvitesTabView()
        .environment(AppServices.preview())
        .environment(AppClock())
}
