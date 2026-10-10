//
//  OpenInviteCardView.swift
//  CampusSync
//
//  One friend invite: landmark, category pill, countdown, attendee count, RSVP.
//  `now` is passed in (from AppClock) by the parent list so every card agrees
//  with the demo clock.
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CategoryPill(category: invite.category)
                Spacer()
                if isHost {
                    Text("Your plan")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                }
            }

            Text(invite.title)
                .font(.title3.bold())
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 6) {
                Label(invite.landmark.displayName, systemImage: invite.landmark.symbol)
                Label(
                    InviteTiming.countdownText(start: invite.startTime, expiresAt: invite.expiresAt, now: now),
                    systemImage: "clock"
                )
                Label(
                    "\(invite.attendeeIDs.count) of \(invite.capacity) going · hosted by \(isHost ? "you" : invite.hostName)",
                    systemImage: "person.2"
                )
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            rsvpButton
        }
        .cardStyle()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "\(invite.category.displayName) plan: \(invite.title) at \(invite.landmark.displayName). "
            + "\(InviteTiming.countdownText(start: invite.startTime, expiresAt: invite.expiresAt, now: now)). "
            + "\(invite.attendeeIDs.count) of \(invite.capacity) going."
        )
    }

    @ViewBuilder
    private var rsvpButton: some View {
        if isGoing {
            Button(action: onToggleRSVP) {
                Label("Going", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.carolinaBlue)
            .foregroundStyle(Theme.navy)
            .minTapTarget()
            .accessibilityHint("Double tap to cancel your RSVP")
        } else if isFull {
            Label("Full", systemImage: "person.fill.xmark")
                .frame(maxWidth: .infinity, minHeight: Theme.minTapTarget)
                .foregroundStyle(.secondary)
        } else {
            Button(action: onToggleRSVP) {
                Label("RSVP", systemImage: "hand.thumbsup")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Theme.textPrimary)
            .minTapTarget()
        }
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
