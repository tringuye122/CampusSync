//
//  OpenInviteCardView.swift
//  CampusSync
//
//  One friend invite: title with a category tag, where and when, who is going, and RSVP.
//  `now` is passed in (from AppClock) by the parent list so every card agrees with the
//  demo clock. Used in the Home carousel and the Invites feed.
//

import SwiftUI

struct OpenInviteCardView: View {
    let invite: OpenInvite
    let now: Date
    let isGoing: Bool
    let isFull: Bool
    let isHost: Bool
    let onToggleRSVP: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(invite.title)
                    .font(.title3.bold())
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Text(invite.category.displayName)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Theme.pillBackground, in: Capsule())
            }

            Text("\(invite.landmark.displayName) · \(timingText)")
                .font(.body)
                .foregroundStyle(Theme.textPrimary)

            HStack(alignment: .center) {
                Text(InviteAttendees.summary(for: invite, isHost: isHost))
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 8)
                rsvpControl
            }
        }
        .cardStyle()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "\(invite.category.displayName) plan: \(invite.title) at \(invite.landmark.displayName). "
            + "\(timingText). \(InviteAttendees.summary(for: invite, isHost: isHost)).")
    }

    /// "starts in 45 min", "happening now · ends in 30 min", or a weekday and time, lowercased
    /// after the landmark so it reads as one line.
    private var timingText: String {
        let text = InviteTiming.countdownText(start: invite.startTime, expiresAt: invite.expiresAt, now: now)
        return text.prefix(1).lowercased() + text.dropFirst()
    }

    @ViewBuilder
    private var rsvpControl: some View {
        if isHost {
            Text("Your plan")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(minHeight: Theme.minTapTarget)
        } else if isGoing {
            Button(action: onToggleRSVP) {
                Label("Going", systemImage: "checkmark")
                    .font(.headline)
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 22)
                    .frame(minHeight: Theme.minTapTarget)
                    .background(Theme.navy, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityHint("Double tap to cancel your RSVP")
        } else if isFull {
            Text("Full")
                .font(.headline)
                .foregroundStyle(.secondary)
                .frame(minHeight: Theme.minTapTarget)
        } else {
            Button(action: onToggleRSVP) {
                Text("RSVP")
                    .font(.headline.weight(.heavy))
                    .foregroundStyle(Theme.navy)
                    .padding(.horizontal, 28)
                    .frame(minHeight: Theme.minTapTarget + 8)
                    .background(Theme.carolinaBlue, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }
}

/// "Maya + 2 going", "You + 1 going", "Maya going".
enum InviteAttendees {
    static func summary(for invite: OpenInvite, isHost: Bool) -> String {
        let host = isHost ? "You" : (invite.hostName.split(separator: " ").first.map(String.init) ?? invite.hostName)
        let others = max(0, invite.attendeeIDs.count - 1)
        return others == 0 ? "\(host) going" : "\(host) + \(others) going"
    }
}

#Preview {
    let now = AppClock().now
    let invites = SampleData.invites(now: now)
    return ScrollView {
        VStack(spacing: 16) {
            OpenInviteCardView(invite: invites[0], now: now, isGoing: false, isFull: false,
                               isHost: false, onToggleRSVP: {})
            OpenInviteCardView(invite: invites[1], now: now, isGoing: true, isFull: false,
                               isHost: false, onToggleRSVP: {})
            OpenInviteCardView(invite: invites[2], now: now, isGoing: false, isFull: true,
                               isHost: true, onToggleRSVP: {})
        }
        .padding()
    }
    .background(Theme.screenBackground)
}
