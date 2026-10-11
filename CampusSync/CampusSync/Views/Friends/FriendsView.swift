//
//  FriendsView.swift
//  CampusSync
//
//  Find students by handle, answer requests, and see your friends. Shown in the Add friends
//  sheet on Schedule > Friends. Lists keep their last values when the network drops.
//

import SwiftUI

struct FriendsView: View {
    @Environment(AppServices.self) private var services
    @State private var viewModel = FriendsViewModel()

    var body: some View {
        List {
            if viewModel.isOffline {
                Section {
                    Label("Offline. Showing what was saved.", systemImage: "wifi.slash")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if let message = viewModel.message {
                Section { Text(message).font(.subheadline).foregroundStyle(.red) }
            }

            searchSection

            if !viewModel.incoming.isEmpty {
                Section("Requests") {
                    ForEach(viewModel.incoming) { request in
                        HStack {
                            studentLabel(request.other)
                            Spacer()
                            Button("Decline") { Task { await viewModel.decline(request, services: services) } }
                                .buttonStyle(.bordered)
                                .tint(Theme.textPrimary)
                                .minTapTarget()
                            Button("Accept") { Task { await viewModel.accept(request, services: services) } }
                                .buttonStyle(.borderedProminent)
                                .tint(Theme.carolinaBlue)
                                .foregroundStyle(Theme.navy)
                                .minTapTarget()
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }

            if !viewModel.outgoing.isEmpty {
                Section("Sent") {
                    ForEach(viewModel.outgoing) { request in
                        HStack {
                            studentLabel(request.other)
                            Spacer()
                            Button("Cancel") { Task { await viewModel.cancel(request, services: services) } }
                                .buttonStyle(.borderless)
                                .tint(Theme.textPrimary)
                                .minTapTarget()
                        }
                    }
                }
            }

            Section("Friends") {
                if viewModel.friends.isEmpty {
                    Text("No friends yet. Search for a handle above.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                ForEach(viewModel.friends) { friend in
                    studentLabel(friend)
                        .swipeActions {
                            Button("Unfriend", role: .destructive) {
                                Task { await viewModel.unfriend(friend, services: services) }
                            }
                        }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.screenBackground)
        .navigationTitle("Add friends")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await viewModel.load(services: services)
            await services.sync.refreshFriendSchedules()
        }
        .task { await viewModel.load(services: services) }
    }

    private var searchSection: some View {
        Section {
            TextField("Search by handle", text: $viewModel.searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .minTapTarget()
            ForEach(viewModel.searchResults) { result in
                HStack {
                    studentLabel(result)
                    Spacer()
                    switch viewModel.relationship(to: result) {
                    case .friend:
                        Text("Friends").foregroundStyle(.secondary)
                    case .requested:
                        Text("Requested").foregroundStyle(.secondary)
                    case .wantsToBeFriends(let request):
                        Button("Accept") { Task { await viewModel.accept(request, services: services) } }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.carolinaBlue)
                            .foregroundStyle(Theme.navy)
                            .minTapTarget()
                    case .stranger:
                        Button("Add") { Task { await viewModel.sendRequest(to: result, services: services) } }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.carolinaBlue)
                            .foregroundStyle(Theme.navy)
                            .minTapTarget()
                    }
                }
                .buttonStyle(.borderless)
            }
            if viewModel.hasSearched && viewModel.searchResults.isEmpty {
                Text("No students match \u{201C}\(viewModel.searchText)\u{201D}.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            Text("Type at least 2 letters of a handle. Friends see when you're in class, never your course names or email.")
        }
        // Re-runs (and cancels the previous run) on every change of the text.
        .task(id: viewModel.searchText) { await viewModel.search(services: services) }
    }

    private func studentLabel(_ student: FriendSummary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(student.displayName).font(.body)
            Text("@\(student.handle)").font(.subheadline).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    NavigationStack { FriendsView() }
        .environment(AppServices.preview())
}
