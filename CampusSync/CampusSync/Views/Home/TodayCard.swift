//
//  TodayCard.swift
//  CampusSync
//
//  Collapsible "Today · 4 classes" card under the hero. Collapsed it shows the next class;
//  expanded it lists today's classes with times and rooms.
//

import SwiftUI

struct TodayCard: View {
    let classes: [SnapshotMeeting]
    let next: SnapshotMeeting?
    @State private var isExpanded = false

    private var title: String {
        switch classes.count {
        case 0: "Today · no classes"
        case 1: "Today · 1 class"
        default: "Today · \(classes.count) classes"
        }
    }

    private var subtitle: String {
        if let next { return "Next: \(next.courseCode) at \(next.startMinutes.clockString)" }
        return classes.isEmpty ? "Enjoy the free day" : "No more classes today"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.snappy) { isExpanded.toggle() }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(.headline).foregroundStyle(Theme.textPrimary)
                        Text(subtitle).font(.subheadline).foregroundStyle(Theme.textPrimary)
                    }
                    Spacer()
                    if !classes.isEmpty {
                        Image(systemName: "chevron.down")
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .allowsHitTesting(!classes.isEmpty)   // not .disabled: that would grey out the text
            .accessibilityHint(isExpanded ? "Hides today's classes" : "Shows today's classes")

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(classes.enumerated()), id: \.offset) { _, meeting in
                        HStack(alignment: .firstTextBaseline) {
                            Text(meeting.courseCode).font(.subheadline.weight(.bold))
                            Spacer()
                            VStack(alignment: .trailing, spacing: 0) {
                                Text("\(meeting.startMinutes.clockString) to \(meeting.endMinutes.clockString)")
                                Text(meeting.location).foregroundStyle(.secondary)
                            }
                            .font(.footnote)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
                .foregroundStyle(Theme.textPrimary)
                .padding(.top, 12)
            }
        }
        .cardStyle()
    }
}

#Preview {
    let classes = SampleData.classes().flatMap(\.snapshotMeetings).filter { $0.weekday == 3 }
    return TodayCard(classes: classes, next: classes.last)
        .padding()
        .background(Theme.screenBackground)
}
