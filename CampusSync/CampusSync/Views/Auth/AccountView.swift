//
//  AccountView.swift
//  CampusSync
//
//  Who you're signed in as, and sign out. Opened from the person icon on Home.
//

import SwiftUI

struct AccountView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

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
        .task { await auth.refresh() }
}
