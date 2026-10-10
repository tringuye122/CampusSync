//
//  AuthView.swift
//  CampusSync
//
//  Sign in / create account, with email and password. UNC addresses only.
//

import SwiftUI

struct AuthView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case signIn = "Sign in"
        case signUp = "Create account"
        var id: String { rawValue }
    }

    @Environment(AuthService.self) private var auth
    @State private var mode: Mode = .signUp
    @State private var email = ""
    @State private var password = ""
    @State private var displayName = ""
    @FocusState private var focused: Field?

    private enum Field { case name, email, password }

    var body: some View {
        AuthScreen(
            title: "CampusSync",
            subtitle: "See when you and your friends are free. Use your @unc.edu email."
        ) {
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: mode) { _, _ in auth.clearMessages() }

            VStack(spacing: 12) {
                if mode == .signUp {
                    TextField("Your name", text: $displayName)
                        .textContentType(.name)
                        .focused($focused, equals: .name)
                        .submitLabel(.next)
                        .onSubmit { focused = .email }
                        .fieldStyle()
                }
                TextField("you@unc.edu", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focused, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focused = .password }
                    .fieldStyle()
                SecureField(mode == .signUp ? "Password (8+ characters)" : "Password", text: $password)
                    .textContentType(mode == .signUp ? .newPassword : .password)
                    .focused($focused, equals: .password)
                    .submitLabel(.go)
                    .onSubmit(submit)
                    .fieldStyle()
            }

            AuthMessages()

            Button(action: submit) {
                if auth.isBusy {
                    ProgressView().tint(Theme.navy)
                } else {
                    Text(mode == .signUp ? "Create account" : "Sign in")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(auth.isBusy)

            if mode == .signIn {
                Button("Forgot password?") {
                    Task { await auth.sendPasswordReset(email: email) }
                }
                .font(.subheadline)
                .minTapTarget()
            }
        }
    }

    private func submit() {
        focused = nil
        Task {
            switch mode {
            case .signUp: await auth.signUp(email: email, password: password, displayName: displayName)
            case .signIn: await auth.signIn(email: email, password: password)
            }
        }
    }
}

extension View {
    /// Rounded field used on the sign-in screens. 44 pt minimum height.
    func fieldStyle() -> some View {
        padding(.horizontal, 14)
            .frame(minHeight: Theme.minTapTarget + 4)
            .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

#Preview {
    AuthView()
        .environment(AuthService(backend: MockAuthBackend(), defaults: UserDefaults(suiteName: "preview-auth")!))
}
