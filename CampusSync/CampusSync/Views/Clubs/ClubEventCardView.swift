//
//  ClubEventCardView.swift
//  CampusSync
//
//  One club event: the club and its access badge, the event, when and where, whether it fits your
//  schedule, and Join Club / Pay Dues.
//

import SwiftUI

struct ClubEventCardView: View {
    let item: ClubsViewModel.Item
    /// Join / Pay Dues, or (when already a member) leave the club.
    let onAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Text(item.clubName)
                    .font(.title3.bold())
                    .foregroundStyle(Theme.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                accessBadge
            }
            Text(item.eventTitle)
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text(whenText)
                .font(.body)
                .foregroundStyle(Theme.textPrimary)
            Text(item.location)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)

            availabilityBar
            actionButton
        }
        .cardStyle()
        .accessibilityElement(children: .contain)
    }

    // MARK: Pieces

    /// Public: soft pill. Dues Required: solid Navy with the amount. Members Only: outlined.
    @ViewBuilder
    private var accessBadge: some View {
        switch item.access {
        case .public:
            Text("Public")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Theme.pillBackground, in: Capsule())
        case .duesRequired:
            Text("Dues Required · $\(item.duesAmount)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Theme.navy, in: Capsule())
        case .membersOnly:
            Text("Members Only")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .overlay(Capsule().strokeBorder(Theme.navy, lineWidth: 1.5))
        }
    }

    @ViewBuilder
    private var availabilityBar: some View {
        switch item.availability {
        case .free:
            // Dark green with white text in light and dark mode (the Success token turns light in dark).
            Label("You are free then", systemImage: "checkmark")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.white)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                .background(Theme.ratingGood, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        case let .conflict(code, start, end):
            Label("Conflicts with \(code) · \(FreeWindowSummary.classRange(start, end))", systemImage: "xmark")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Theme.danger)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                .background(Theme.dangerSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        if item.isJoined {
            // The same button toggles: tap again to leave.
            Button(action: onAction) {
                VStack(spacing: 0) {
                    Label(item.access == .duesRequired ? "Dues paid" : "Joined", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                    Text("Tap to leave")
                        .font(.caption)
                }
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 56)
                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.navy, lineWidth: 2))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(item.access == .duesRequired ? "Dues paid, you are a member" : "You joined this club")
            .accessibilityHint("Leaves the club")
        } else {
            Button(action: onAction) {
                Text(item.access == .duesRequired ? "Pay Dues · $\(item.duesAmount)" : "Join Club")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Theme.navy)
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .background(Theme.carolinaBlue, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    /// "Tue, Oct 13 · 7:00–8:00 PM"
    private var whenText: String {
        let calendar = Calendar.current
        let day = item.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        let start = item.start.minutesSinceMidnight(in: calendar)
        let end = calendar.isDate(item.end, inSameDayAs: item.start) ? item.end.minutesSinceMidnight(in: calendar) : 24 * 60
        return "\(day) · \(FreeWindowSummary.classRange(start, end))"
    }
}

#Preview {
    let now = AppClock().now
    let base = ClubsViewModel.Item(
        id: "1", clubID: "c1", clubName: "AR/VR UNC", access: .public, duesAmount: 0,
        eventTitle: "General meeting", location: "Student Union, Rm 2518",
        start: now.addingTimeInterval(7200), end: now.addingTimeInterval(10800),
        availability: .free, isJoined: false)
    var dues = base
    dues.id = "2"; dues.clubName = "Rams Robotics"; dues.access = .duesRequired; dues.duesAmount = 25
    dues.availability = .conflict(courseCode: "LING 460", startMinutes: 17 * 60, endMinutes: 18 * 60 + 15)
    var joined = base
    joined.id = "3"; joined.access = .membersOnly; joined.isJoined = true
    return ScrollView {
        VStack(spacing: 14) {
            ClubEventCardView(item: base, onAction: {})
            ClubEventCardView(item: dues, onAction: {})
            ClubEventCardView(item: joined, onAction: {})
        }
        .padding()
    }
    .background(Theme.screenBackground)
}
