//
//  VerifyEmailView.swift
//  CampusSync
//
//  Shown after sign-up until the student opens the link in their verification
//  email. Firestore access stays blocked until the email is verified.
//

import SwiftUI

struct VerifyEmailView: View {
    let email: String
    @Environment(AuthService.self) private var auth
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        AuthScreen(
            title: "Check your email",
            subtitle: "We sent a verification link to \(email)."
        ) {
            Text("Open the link, then come back here. Check your spam folder if you don't see it.")
                .foregroundStyle(.secondary)

            AuthMessages()

            Button {
                Task { await auth.confirmVerification() }
            } label: {
                if auth.isBusy { ProgressView().tint(Theme.navy) } else { Text("I've verified") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(auth.isBusy)

            Button("Resend email") { Task { await auth.resendVerification() } }
                .minTapTarget()
                .disabled(auth.isBusy)

            Button("Use a different account", role: .destructive) { auth.signOut() }
                .minTapTarget()
        }
        // Coming back from the mail app: check again without making them tap.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await auth.refresh() } }
        }
    }
}

#Preview {
    VerifyEmailView(email: "you@unc.edu")
        .environment(AuthService(backend: MockAuthBackend(), defaults: UserDefaults(suiteName: "preview-auth")!))
}
