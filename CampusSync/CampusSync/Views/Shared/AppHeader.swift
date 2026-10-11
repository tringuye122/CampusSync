//
//  AppHeader.swift
//  CampusSync
//
//  The profile header at the top of every tab: avatar (tap for Account),
//  @handle, the university logo, then a Verified Member pill and "CS '28".
//

import SwiftUI

struct AppHeader: View {
    @Environment(AuthService.self) private var auth
    @Environment(AppServices.self) private var services
    @State private var model = ProfileHeaderViewModel()
    @State private var showingAccount = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                Button { showingAccount = true } label: {
                    Avatar(name: auth.account?.displayName ?? "", size: 64, isRinged: true)
                }
                .buttonStyle(.plain)
                .minTapTarget()
                .accessibilityLabel("Account")
                .accessibilityHint("Opens your account")

                Text(handleText)
                    .font(.title2.bold())
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer(minLength: 8)
                UNCWordmark()
            }

            detailLine
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardBackground)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.hairline.opacity(0.5)).frame(height: 1) }
        .sheet(isPresented: $showingAccount) { AccountView() }
        .task { await model.load(services: services) }
        .onChange(of: services.dataVersion) { Task { await model.load(services: services) } }
        .onChange(of: services.sync.changeCount) { Task { await model.load(services: services) } }
    }

    private var handleText: String {
        auth.account.map { "@\($0.handle)" } ?? "@you"
    }

    /// "CS '28", with the Verified Member pill (when earned) and the Demo pill (in demo mode) in front.
    private var detailLine: some View {
        let parts = [auth.account?.affiliation].compactMap { $0 }
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                modePill
                if model.isVerifiedMember { verifiedPill }
                if !parts.isEmpty { detailText(parts) }
            }
            VStack(alignment: .leading, spacing: 6) {
                modePill
                if model.isVerifiedMember { verifiedPill }
                if !parts.isEmpty { detailText(parts) }
            }
        }
    }

    /// Always one of the two, so which data you are looking at is never in doubt.
    @ViewBuilder private var modePill: some View {
        if services.isDemoMode { demoPill } else { livePill }
    }

    /// Real Firebase data. Green symbol on the neutral pill fill so the text keeps its contrast.
    private var livePill: some View {
        Label {
            Text("Live")
        } icon: {
            Image(systemName: "dot.radiowaves.left.and.right")
                .foregroundStyle(Theme.success)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(Theme.textPrimary)
        .lineLimit(1)
        .fixedSize()   // one line, never wrapped inside the capsule
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Theme.pillBackground, in: Capsule())
        .accessibilityLabel("Live data")
    }

    /// Shown whenever demo data is on, so it is never mistaken for live data.
    private var demoPill: some View {
        Label("Demo mode", systemImage: "play.rectangle.fill")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.cautionText)
            .lineLimit(1)
            .fixedSize()   // icon and text stay on one line
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.cautionSurface, in: Capsule())
    }

    private var verifiedPill: some View {
        Text("Verified Member")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.pillBackground, in: Capsule())
    }

    private func detailText(_ parts: [String]) -> some View {
        Text(parts.joined(separator: " · "))
            .font(.subheadline)
            .foregroundStyle(Theme.textPrimary)
    }
}

extension View {
    /// A tab's screen: the profile header on top, the content below, on the standard background.
    func withAppHeader() -> some View {
        VStack(spacing: 0) {
            AppHeader()
            self
        }
        .background(Theme.screenBackground)
    }
}

#Preview {
    let backend = MockAuthBackend(signedInEmail: "justin@unc.edu")
    backend.seed(email: "justin@unc.edu", password: "password1", displayName: "Justin Nguyen", handle: "justin")
    let auth = AuthService(backend: backend, defaults: UserDefaults(suiteName: "preview-header")!)
    return Color.clear
        .withAppHeader()
        .environment(auth)
        .environment(AppServices.preview())
        .task { await auth.refresh() }
}
