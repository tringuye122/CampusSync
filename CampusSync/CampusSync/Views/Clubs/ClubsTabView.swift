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

    var body: some View {
        VStack(spacing: 12) {
            FilterChips(values: ClubFilter.allCases, selection: $filter, layout: .equalWidth) { $0.rawValue }
                .padding(.top, 12)
            content
        }
        .withAppHeader()
        .onAppear { Task { await viewModel.load(services: services, now: clock.now) } }
        .onChange(of: services.sync.changeCount) { Task { await viewModel.load(services: services, now: clock.now) } }
        .onChange(of: services.dataVersion) { Task { await viewModel.load(services: services, now: clock.now) } }
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
            ContentUnavailableView(emptyTitle, systemImage: "star.circle", description: Text(emptyDetail))
        } else {
            ScrollView {
                LazyVStack(spacing: 14) {
                    ForEach(items) { item in
                        ClubEventCardView(item: item) {
                            Task { await viewModel.act(on: item, services: services) }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 4)
            }
        }
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
