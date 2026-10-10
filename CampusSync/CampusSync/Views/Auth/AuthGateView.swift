//
//  AuthGateView.swift
//  CampusSync
//
//  Shows the right screen for the sign-in state, and the app itself once the
//  student is signed in with a verified @unc.edu account and a handle.
//

import SwiftUI

struct AuthGateView<Content: View>: View {
    @Environment(AuthService.self) private var auth
    @ViewBuilder let content: () -> Content

    var body: some View {
        switch auth.state {
        case .loading:
            ProgressView("Loading…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.screenBackground)
        case .signedOut:
            AuthView()
        case .needsVerification(let email):
            VerifyEmailView(email: email)
        case .needsProfile(_, let suggestedName):
            ProfileSetupView(suggestedName: suggestedName)
        case .connectionProblem(let email):
            ConnectionProblemView(email: email)
        case .signedIn:
            content()
        }
    }
}

/// Shared look for the sign-in screens.
struct AuthScreen<Content: View>: View {
    let title: String
    let subtitle: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.largeTitle)
                        .foregroundStyle(Theme.carolinaBlue)
                        .accessibilityHidden(true)
                    Text(title)
                        .font(.largeTitle.bold())
                        .foregroundStyle(Theme.textPrimary)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                content()
            }
            .padding(24)
        }
        .background(Theme.screenBackground)
    }
}

/// Primary button style for the sign-in screens: Carolina Blue fill, Navy text.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(Theme.navy)
            .frame(maxWidth: .infinity, minHeight: Theme.minTapTarget + 8)
            .background(Theme.carolinaBlue.opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Error and info lines shown under a form.
struct AuthMessages: View {
    @Environment(AuthService.self) private var auth

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let error = auth.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.red)
            }
            if let info = auth.infoMessage {
                Label(info, systemImage: "info.circle.fill")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
            }
        }
    }
}

struct ConnectionProblemView: View {
    let email: String
    @Environment(AuthService.self) private var auth

    var body: some View {
        AuthScreen(title: "No connection", subtitle: "Signed in as \(email)") {
            Text("We couldn't load your profile. Check your connection and try again.")
                .foregroundStyle(.secondary)
            Button("Try again") { Task { await auth.refresh() } }
                .buttonStyle(PrimaryButtonStyle())
            Button("Sign out", role: .destructive) { auth.signOut() }
                .minTapTarget()
        }
    }
}
