//
//  DayChips.swift
//  CampusSync
//
//  Mon Tue Wed Thu Fri chips; the selected day is Carolina Blue.
//

import SwiftUI

struct DayChips: View {
    @Binding var selection: Weekday

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Weekday.allCases) { day in
                Button { selection = day } label: {
                    Text(day.shortLabel)
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: Theme.minTapTarget + 8)
                        .background(
                            day == selection ? Theme.carolinaBlue : Theme.cardBackground,
                            in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .foregroundStyle(day == selection ? Theme.navy : Theme.textPrimary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(day.fullName)
                .accessibilityAddTraits(day == selection ? [.isSelected, .isButton] : .isButton)
            }
        }
    }

    /// Today's weekday, or Monday on a weekend, so the chips always start on a school day.
    static func initialDay(now: Date, calendar: Calendar = .current) -> Weekday {
        Weekday(rawValue: calendar.component(.weekday, from: now)) ?? .mon
    }
}

#Preview {
    @Previewable @State var day = Weekday.tue
    return DayChips(selection: $day).padding().background(Theme.screenBackground)
}
