//
//  ProfileSetupView.swift
//  CampusSync
//
//  First sign-in after verifying: pick a display name and a unique @handle.
//  Friends find you by handle, so it is checked live against Firestore.
//

import SwiftUI

struct ProfileSetupView: View {
    let suggestedName: String

    @Environment(AuthService.self) private var auth
    @State private var displayName = ""
    @State private var handle = ""
    @State private var major = ""
    @State private var classYear = ""
    @State private var availability: AuthService.HandleAvailability = .unchecked

    var body: some View {
        AuthScreen(title: "Almost there", subtitle: "Pick how friends will find you.") {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Your name", text: $displayName)
                    .textContentType(.name)
                    .fieldStyle()

                HStack(spacing: 2) {
                    Text("@").foregroundStyle(.secondary)
                    TextField("handle", text: $handle)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .fieldStyle()

                availabilityLabel
                    .font(.footnote)

                Text("Handles are 3 to 20 characters: lowercase letters, numbers and underscores. You can't change it later.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                TextField("Major (optional, for example CS)", text: $major)
                    .fieldStyle()
                TextField("Class year (optional, for example 2028)", text: $classYear)
                    .keyboardType(.numberPad)
                    .fieldStyle()
                Text("Shown in your header, like CS '28. You can change these later.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            AuthMessages()

            Button {
                Task { await auth.createProfile(displayName: displayName, handle: handle, major: major, classYear: classYear) }
            } label: {
                if auth.isBusy { ProgressView().tint(Theme.navy) } else { Text("Continue") }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(auth.isBusy || availability == .taken || availability == .checking)

            Button("Sign out", role: .destructive) { auth.signOut() }
                .minTapTarget()
        }
        .onAppear { if displayName.isEmpty { displayName = suggestedName } }
        // Re-checks 0.4 s after the last keystroke; changing `handle` cancels the pending check.
        .task(id: handle) {
            guard !handle.isEmpty else {
                availability = .unchecked
                return
            }
            availability = .checking
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            availability = await auth.checkHandle(handle)
        }
    }

    @ViewBuilder
    private var availabilityLabel: some View {
        switch availability {
        case .unchecked:
            EmptyView()
        case .checking:
            Label("Checking…", systemImage: "hourglass").foregroundStyle(.secondary)
        case .available:
            Label("@\(AuthValidator.normalizeHandle(handle)) is available", systemImage: "checkmark.circle.fill")
                .foregroundStyle(Theme.categoryFitness)
        case .taken:
            Label("That handle is taken", systemImage: "xmark.circle.fill").foregroundStyle(.red)
        case .invalid(let reason):
            Label(reason, systemImage: "exclamationmark.circle.fill").foregroundStyle(.red)
        case .unknown:
            Label("Couldn't check right now. You can still try Continue.", systemImage: "wifi.slash")
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ProfileSetupView(suggestedName: "Pat Example")
        .environment(AuthService(backend: MockAuthBackend(), defaults: UserDefaults(suiteName: "preview-auth")!))
}
