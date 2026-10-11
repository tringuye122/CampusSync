//
//  ClubsTabView.swift
//  CampusSync
//
//  Upcoming club events under the profile header. Each card says whether the event fits your class
//  schedule. Filters: All clubs, Free for me (no conflict), Joined. Club events are public.
//

import SwiftUI

struct ClubsTabView: View {
    @Environment(AppServices.self) private var services
    @Environment(AppClock.self) private var clock
    @State private var viewModel = ClubsViewModel()
    @State private var filter = ClubFilter.all
    @State private var isComposing = false
    /// A joined dues club the user tapped to leave; confirmed first since leaving clears dues paid.
    @State private var leaving: ClubsViewModel.Item?
    @State private var deleting: ClubsViewModel.Item?

    var body: some View {
        VStack(spacing: 12) {
            FilterChips(values: ClubFilter.allCases, selection: $filter, layout: .equalWidth) { $0.rawValue }
                .padding(.top, 12)
            ZStack(alignment: .bottomTrailing) {
                content
                postButton
            }
        }
        .withAppHeader()
        .onAppear { Task { await viewModel.load(services: services, now: clock.now) } }
        .onChange(of: services.sync.changeCount) { Task { await viewModel.load(services: services, now: clock.now) } }
        .onChange(of: services.dataVersion) { Task { await viewModel.load(services: services, now: clock.now) } }
        .sheet(isPresented: $isComposing) {
            ComposeClubEventSheet(clubs: viewModel.joinedClubs, now: clock.now) { draft in
                await viewModel.post(draft, services: services, now: clock.now)
            }
            .presentationDetents([.large])
        }
        .confirmationDialog(
            "Leave \(leaving?.clubName ?? "this club")?",
            isPresented: Binding(get: { leaving != nil }, set: { if !$0 { leaving = nil } }),
            titleVisibility: .visible
        ) {
            Button("Leave club", role: .destructive) {
                if let item = leaving { Task { await viewModel.leave(item, services: services, now: clock.now) } }
                leaving = nil
            }
            Button("Stay", role: .cancel) { leaving = nil }
        } message: {
            Text("Your dues paid status for this club is removed, and you would pay again to rejoin.")
        }
        .confirmationDialog(
            "Remove \"\(deleting?.eventTitle ?? "this event")\"?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove event", role: .destructive) {
                if let item = deleting { Task { await viewModel.delete(item, services: services, now: clock.now) } }
                deleting = nil
            }
            Button("Keep", role: .cancel) { deleting = nil }
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

    @ViewBuilder
    private var content: some View {
        let items = viewModel.visibleItems(filter: filter)
        if items.isEmpty {
            ContentUnavailableView(emptyTitle, systemImage: "star.circle", description: Text(emptyDetail).foregroundStyle(Theme.textPrimary))
        } else {
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(items) { item in
                        ClubEventCardView(item: item, isBusy: viewModel.isBusy(item)) {
                            if !item.isJoined {
                                Task { await viewModel.act(on: item, services: services, now: clock.now) }
                            } else if item.access == .duesRequired {
                                leaving = item   // asks first: leaving clears dues paid
                            } else {
                                Task { await viewModel.leave(item, services: services, now: clock.now) }
                            }
                        }
                        .contextMenu {
                            if item.isMine {
                                Button("Remove event", systemImage: "trash", role: .destructive) { deleting = item }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
                // Room so the floating button never covers the last card.
                .padding(.bottom, 96)
            }
        }
    }

    private var postButton: some View {
        Button {
            if services.isDemoMode {
                viewModel.errorMessage = ClubsViewModel.demoPostMessage
            } else {
                isComposing = true
            }
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
        .accessibilityLabel("Post a club event")
    }

    private var emptyTitle: String {
        switch filter {
        case .all: "No club events yet"
        case .freeForMe: "Nothing fits your schedule"
        case .joined: "No joined clubs yet"
        }
    }

    private var emptyDetail: String {
        switch filter {
        case .all: "Upcoming club events will show up here."
        case .freeForMe: "Every upcoming event overlaps one of your classes."
        case .joined: "Join a club and its events will show up here."
        }
    }
}

#Preview {
    ClubsTabView()
        .environment(AppServices.preview())
        .environment(AppClock())
        .environment(AppRouter())
        .environment(AuthService(backend: MockAuthBackend(), defaults: UserDefaults(suiteName: "preview-auth")!))
}

#Preview("New account") {
    ClubsTabView()
        .environment(AppServices.previewEmpty())
        .environment(AppClock())
        .environment(AppRouter())
        .environment(AuthService(backend: MockAuthBackend(), defaults: UserDefaults(suiteName: "preview-auth")!))
}
