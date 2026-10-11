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
    @State private var isUpdatingSharing = false
    @State private var sharingMessage: String?
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
                            sharingMessage = nil
                            isUpdatingSharing = true
                            // Publishes the meeting times, or removes them all when switched off.
                            Task {
                                defer { isUpdatingSharing = false }
                                do {
                                    try await services.schedule.setSharesScheduleWithFriends(shares)
                                } catch ScheduleSharingError.notConfirmed {
                                    sharingMessage = shares
                                        ? "Saved. Friends will see your times once you are back online."
                                        : "Saved, but the server has not confirmed it yet. Friends can still see your times until you are back online."
                                } catch {
                                    sharesSchedule = services.schedule.sharesScheduleWithFriends   // what is really stored
                                    sharingMessage = "Couldn't change sharing. Try again."
                                }
                            }
                        }))
                    .tint(Theme.success)
                        .disabled(services.isDemoMode || isUpdatingSharing)   // demo data is never shared; one change at a time
                        .minTapTarget()
                        .onAppear { sharesSchedule = services.schedule.sharesScheduleWithFriends }
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Friends see when you have class and where, never course names or instructors. Turn this off to remove your times from the server.")
                        if let sharingMessage {
                            Text(sharingMessage).foregroundStyle(Theme.textPrimary).fontWeight(.semibold)
                        }
                    }
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
                        .disabled(services.isSwitchingDemo)   // a switch finishes before the next starts
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
