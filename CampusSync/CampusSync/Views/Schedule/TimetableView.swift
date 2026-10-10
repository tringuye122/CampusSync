//
//  TimetableView.swift
//  CampusSync
//
//  Weekly grid, Monday to Friday, covering the waking-hours window. Class blocks
//  are solid Carolina Blue; usable free gaps are shaded with a dashed outline.
//  Tapping a class opens the professor rating sheet.
//

import SwiftUI

struct TimetableView: View {
    let viewModel: ScheduleViewModel
    @Environment(AppClock.self) private var clock

    private let hourHeight: CGFloat = 56
    private let axisWidth: CGFloat = 44

    private var windowStart: Int { viewModel.settings.dayStartMinutes }
    private var windowEnd: Int { viewModel.settings.dayEndMinutes }
    private var hourCount: Int { (windowEnd - windowStart) / 60 }
    private var gridHeight: CGFloat { CGFloat(windowEnd - windowStart) * hourHeight / 60 }
    private var todayWeekday: Int { Calendar.current.component(.weekday, from: clock.now) }

    var body: some View {
        ScrollView {
            VStack(spacing: 4) {
                dayHeader
                HStack(alignment: .top, spacing: 0) {
                    timeAxis
                    ForEach(Weekday.allCases) { day in
                        dayColumn(day)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .background(Theme.screenBackground)
    }

    // MARK: Header and axis

    private var dayHeader: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: axisWidth, height: 1)
            ForEach(Weekday.allCases) { day in
                let isToday = day.rawValue == todayWeekday
                Text(day.shortLabel)
                    .font(.caption.bold())
                    .foregroundStyle(isToday ? Theme.navy : Theme.textPrimary)
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .background(isToday ? Theme.carolinaBlue : .clear, in: Capsule())
                    .accessibilityLabel(isToday ? "\(day.fullName), today" : day.fullName)
            }
        }
    }

    private var timeAxis: some View {
        ZStack(alignment: .topTrailing) {
            ForEach(0...hourCount, id: \.self) { hour in
                Text((windowStart + hour * 60).clockString.replacingOccurrences(of: ":00", with: ""))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .offset(y: CGFloat(hour) * hourHeight - 7)
                    .padding(.trailing, 4)
            }
        }
        .frame(width: axisWidth, height: gridHeight, alignment: .topTrailing)
        .accessibilityHidden(true)
    }

    // MARK: Day column

    private func dayColumn(_ day: Weekday) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(0...hourCount, id: \.self) { hour in
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(height: 0.5)
                    .offset(y: CGFloat(hour) * hourHeight)
            }

            ForEach(viewModel.freeSlots(on: day)) { slot in
                freeSlotView(slot, day: day)
            }

            ForEach(viewModel.classes(on: day)) { item in
                classBlock(item, day: day)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: gridHeight, alignment: .topLeading)
    }

    private func yOffset(_ minutes: Int) -> CGFloat {
        CGFloat(max(minutes, windowStart) - windowStart) * hourHeight / 60
    }

    private func height(from start: Int, to end: Int) -> CGFloat {
        CGFloat(min(end, windowEnd) - max(start, windowStart)) * hourHeight / 60
    }

    private func freeSlotView(_ slot: FreeSlot, day: Weekday) -> some View {
        let blockHeight = height(from: slot.startMinutes, to: slot.endMinutes)
        return RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Theme.carolinaBlue.opacity(0.15))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Theme.carolinaBlue.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
            .overlay(alignment: .top) {
                if blockHeight >= 44 {
                    Text(slot.durationMinutes.durationString)
                        .font(.caption2)
                        .foregroundStyle(Theme.textPrimary)
                        .minimumScaleFactor(0.7)
                        .lineLimit(1)
                        .padding(.top, 4)
                }
            }
            .frame(height: blockHeight)
            .padding(2)
            .offset(y: yOffset(slot.startMinutes))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                "Free on \(day.fullName), \(slot.startMinutes.clockString) to \(slot.endMinutes.clockString), \(slot.durationMinutes.durationString)"
            )
    }

    private func classBlock(_ item: ClassSchedule, day: Weekday) -> some View {
        let blockHeight = height(from: item.startMinutes, to: item.endMinutes)
        return Button {
            viewModel.selectedClass = item
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.courseCode)
                    .font(.caption2.bold())
                if blockHeight >= 56 {
                    Text(item.startMinutes.clockString)
                        .font(.caption2)
                }
            }
            .foregroundStyle(Theme.navy)
            .minimumScaleFactor(0.7)
            .lineLimit(2)
            .padding(4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.carolinaBlue, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(height: blockHeight)
        .padding(2)
        .offset(y: yOffset(item.startMinutes))
        .accessibilityLabel(
            "\(item.courseCode), \(item.title), \(day.fullName) \(item.startMinutes.clockString) to \(item.endMinutes.clockString), \(item.building) \(item.room)"
        )
        .accessibilityHint("Shows the instructor rating")
    }
}

#Preview {
    let services = AppServices.preview()
    let viewModel = ScheduleViewModel()
    return TimetableView(viewModel: viewModel)
        .environment(AppClock())
        .task { await viewModel.load(from: services.schedule) }
}
