//
//  AccountView.swift
//  CampusSync
//
//  Who you're signed in as, and sign out. Opened from the person icon on Home.
//

import SwiftUI

struct AccountView: View {
    @Environment(AuthService.self) private var auth
    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var sharesSchedule = true

    var body: some View {
        NavigationStack {
            List {
                if let account = auth.account {
                    Section {
                        LabeledContent("Name", value: account.displayName)
                        LabeledContent("Handle", value: "@\(account.handle)")
                        LabeledContent("Email", value: account.email)
                    } footer: {
                        Text("Friends find you by your handle. Your email is never shown to other students.")
                    }
                }
                Section {
                    NavigationLink {
                        FriendsView()
                    } label: {
                        Label("Friends", systemImage: "person.2.fill")
                    }
                    .minTapTarget()
                }
                Section {
                    Toggle("Share my class times with friends", isOn: Binding(
                        get: { sharesSchedule },
                        set: { shares in
                            sharesSchedule = shares
                            // Publishes the meeting times, or removes them all when switched off.
                            Task { try? await services.schedule.setSharesScheduleWithFriends(shares) }
                        }))
                        .minTapTarget()
                        .onAppear { sharesSchedule = services.schedule.sharesScheduleWithFriends }
                } footer: {
                    Text("Friends see when you have class and where, never course names or instructors. Turn this off to remove your times from the server.")
                }
                Section {
                    Button("Sign out", role: .destructive) {
                        auth.signOut()
                        dismiss()
                    }
                    .minTapTarget()
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.screenBackground)
            .navigationTitle("Account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

#Preview {
    let backend = MockAuthBackend(signedInEmail: "pat@unc.edu")
    backend.seed(email: "pat@unc.edu", password: "password1", displayName: "Pat Example", handle: "pat")
    let auth = AuthService(backend: backend, defaults: UserDefaults(suiteName: "preview-auth")!)
    return AccountView()
        .environment(auth)
        .environment(AppServices.preview())
        .task { await auth.refresh() }
}
