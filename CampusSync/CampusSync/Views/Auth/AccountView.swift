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
    @State private var major = ""
    @State private var classYear = ""

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
                    TextField("Major (for example CS)", text: $major)
                        .minTapTarget()
                    TextField("Class year (for example 2028)", text: $classYear)
                        .keyboardType(.numberPad)
                        .minTapTarget()
                    Button("Save") {
                        Task { await auth.updateDetails(major: major, classYear: classYear) }
                    }
                    // Navy in light mode; the same token turns near-white in dark mode, where navy
                    // text would vanish against the dark row.
                    .foregroundStyle(Theme.textPrimary)
                    .disabled(auth.isBusy)
                    .minTapTarget()
                } header: {
                    Text("Profile")
                } footer: {
                    Text("Shown in your header, like CS '28. Friends can see them. Both are optional.")
                }
                Section {
                    Toggle("Share my class times with friends", isOn: Binding(
                        get: { sharesSchedule },
                        set: { shares in
                            sharesSchedule = shares
                            // Publishes the meeting times, or removes them all when switched off.
                            Task { try? await services.schedule.setSharesScheduleWithFriends(shares) }
                        }))
                    .tint(Theme.success)
                        .disabled(services.isDemoMode)   // demo data is never shared
                        .minTapTarget()
                        .onAppear { sharesSchedule = services.schedule.sharesScheduleWithFriends }
                } footer: {
                    Text("Friends see when you have class and where, never course names or instructors. Turn this off to remove your times from the server.")
                }
                Section {
                    Toggle("Demo mode", isOn: Binding(
                        get: { services.isDemoMode },
                        set: { on in
                            Task {
                                if on { await services.enterDemoMode(account: auth.account) } else { await services.exitDemoMode() }
                            }
                        }))
                        .tint(Theme.success)
                        .minTapTarget()
                } header: {
                    Text("Demo")
                } footer: {
                    Text("Swaps in demo friends, schedules and invites and sets the clock to Tue, Oct 13, 12:30 PM. Your account, sign-in and clubs stay live. Turn it off to delete the demo data and go back to live.")
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
            .onAppear {
                major = auth.account?.major ?? ""
                classYear = auth.account?.classYear.map(String.init) ?? ""
            }
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
