//
//  FriendFreeNowCard.swift
//  CampusSync
//
//  One "Friends free now" card: the friend's avatar and name, a line about their status, and a
//  status pill (Mutual Window, Free Now, In Class, No Schedule). Pills pair color with a symbol.
//  Cards sit side by side in a horizontal carousel on Home.
//

import SwiftUI

struct FriendFreeNowCard: View {
    static let width: CGFloat = 160

    let status: FriendStatus

    var body: some View {
        VStack(spacing: 8) {
            Avatar(name: String(firstName.prefix(1)), size: 64)   // one letter, as in the design
            Text(firstName)
                .font(.headline.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            pill
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .cardStyle()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(status.name): \(pillText). \(detail).")
        .accessibilityHint("Opens your schedules side by side")
    }

    private var firstName: String {
        status.name.split(separator: " ").first.map(String.init) ?? status.name
    }

    private var detail: String {
        switch status.state {
        case .mutualFree(let until): "Free until \(until.clockString)"
        case .free(let minutes?): "Free for \(minutes.spacedDuration)"
        case .free(minutes: nil): "Free rest of today"
        case .inClass(let until): "In class until \(until.clockString)"
        case .notShared: "Schedule not shared"
        }
    }

    private var pillText: String {
        switch status.state {
        case .mutualFree: "Mutual Window"
        case .free: "Free Now"
        case .inClass: "In Class"
        case .notShared: "No Schedule"
        }
    }

    private var pill: some View {
        HStack(spacing: 4) {
            if let symbol { Image(systemName: symbol).imageScale(.small) }
            Text(pillText)
        }
        .font(.footnote.weight(.bold))
        .foregroundStyle(pillForeground)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(pillBackground, in: Capsule())
        // Navy on the dark-mode card is nearly invisible, so every pill gets an edge.
        .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
    }

    private var symbol: String? {
        switch status.state {
        case .mutualFree: "person.2.fill"
        case .free: nil
        case .inClass: "book.closed.fill"
        case .notShared: "eye.slash"
        }
    }

    private var pillBackground: Color {
        switch status.state {
        case .mutualFree: Theme.navy
        case .free: Theme.carolinaBlue
        case .inClass, .notShared: Theme.pillBackground
        }
    }

    private var pillForeground: Color {
        switch status.state {
        case .mutualFree: .white
        case .free: Theme.navy
        case .inClass, .notShared: Theme.textPrimary
        }
    }
}

#Preview {
    let mine = SampleData.classes().map(\.meeting)
    let calendar = Calendar.current
    let tuesday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 12, minute: 15))!
    var friends = SampleData.friends().map { FriendSchedule(id: $0.id, name: $0.displayName, meetings: $0.classes) }
    friends.append(FriendSchedule(id: "x", name: "Sam Lee", meetings: []))
    let statuses = FriendsFreeNow.statuses(mine: mine, friends: friends, now: tuesday)
    return ScrollView(.horizontal) {
        HStack { ForEach(statuses) { FriendFreeNowCard(status: $0).frame(width: FriendFreeNowCard.width) } }.padding()
    }
    .background(Theme.screenBackground)
}
