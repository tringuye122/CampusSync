//
//  TimetableView.swift
//  CampusSync
//
//  One day at a time (Mon to Fri chips live in the parent). Class blocks are solid Carolina Blue;
//  usable free gaps are dashed boxes labelled "Free · 3 h 15 min". Free gaps already account for
//  the 30 minute minimum, waking hours, and the walking buffer between buildings.
//

import SwiftUI

struct TimetableView: View {
    let viewModel: ScheduleViewModel
    let day: Weekday
    @Environment(AppClock.self) private var clock

    var body: some View {
        let now = clock.now
        let isToday = Weekday(rawValue: Calendar.current.component(.weekday, from: now)) == day
        TimelineGrid(nowMinutes: isToday ? now.minutesSinceMidnight() : nil) { metrics in
            ZStack(alignment: .topLeading) {
                ForEach(viewModel.freeSlots(on: day)) { slot in
                    freeBlock(slot, metrics: metrics)
                }
                ForEach(viewModel.classes(on: day)) { cls in
                    classBlock(cls, metrics: metrics)
                }
                ForEach(viewModel.events(on: day, now: now)) { event in
                    eventBlock(event, metrics: metrics)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func classBlock(_ cls: ClassSchedule, metrics: TimelineMetrics) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(cls.courseCode)
                .font(.headline.weight(.heavy))
            Text("\(cls.startMinutes.clockString) – \(cls.endMinutes.clockString)")
                .font(.subheadline)
            Text(location(of: cls))
                .font(.subheadline)
        }
        .foregroundStyle(Theme.navy)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: max(36, metrics.height(from: cls.startMinutes, to: cls.endMinutes) - 3), alignment: .top)
        .background(Theme.carolinaBlue, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .clipped()
        .offset(y: metrics.y(cls.startMinutes) + 1)
        // VoiceOver reads the whole block as one sentence.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(cls.courseCode), \(cls.startMinutes.clockString) to \(cls.endMinutes.clockString), \(location(of: cls))")
    }

    /// A joined club's event or an invite you are going to: solid navy, so it stands apart from
    /// Carolina Blue classes and dashed free time. Drawn on top, inset so a class under it still shows.
    private func eventBlock(_ event: CalendarEvent, metrics: TimelineMetrics) -> some View {
        let calendar = Calendar.current
        let start = event.start.minutesSinceMidnight(in: calendar)
        let end = calendar.isDate(event.end, inSameDayAs: event.start) ? event.end.minutesSinceMidnight(in: calendar) : 24 * 60
        let symbol = event.kind == .club ? "person.3.fill" : "paperplane.fill"
        return VStack(alignment: .leading, spacing: 1) {
            Label(event.title, systemImage: symbol)
                .font(.subheadline.weight(.heavy))
                .lineLimit(1)
            Text("\(start.clockString) – \(end.clockString) · \(event.place)")
                .font(.footnote)
                .lineLimit(1)
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: max(36, metrics.height(from: start, to: end) - 3), alignment: .top)
        .background(Theme.navy, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Theme.hairline, lineWidth: 1))
        .clipped()
        .padding(.leading, 36)
        .offset(y: metrics.y(start) + 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(event.kind == .club ? "Club event" : "Plan"): \(event.title), \(start.clockString) to \(end.clockString), \(event.place)")
    }

    private func freeBlock(_ slot: FreeSlot, metrics: TimelineMetrics) -> some View {
        Text("Free · \(slot.durationMinutes.spacedDuration)")
            .font(.headline)
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: max(30, metrics.height(from: slot.startMinutes, to: slot.endMinutes) - 3))
            .background(
                // Solid fill first so the hour lines do not show through the box.
                RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.cardBackground))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.carolinaBlue, style: StrokeStyle(lineWidth: 2.5, dash: [5, 5])))
            .offset(y: metrics.y(slot.startMinutes) + 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "Free for \(slot.durationMinutes.spacedDuration), \(slot.startMinutes.clockString) to \(slot.endMinutes.clockString)")
    }

    private func location(of cls: ClassSchedule) -> String {
        [cls.building, cls.room].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

#Preview {
    let model = ScheduleViewModel()
    return TimetableView(viewModel: model, day: .tue)
        .environment(AppClock())
        .environment(AppServices.preview())
        .task { await model.load(from: AppServices.preview().schedule) }
        .background(Theme.screenBackground)
}
