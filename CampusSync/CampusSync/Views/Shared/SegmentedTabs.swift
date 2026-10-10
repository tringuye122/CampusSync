//
//  SegmentedTabs.swift
//  CampusSync
//
//  The large rounded segmented control from the designs (Timetable / Friends / Classes): a pale
//  track with a white pill behind the selected segment.
//

import SwiftUI

struct SegmentedTabs<Value: Hashable & Identifiable>: View {
    let values: [Value]
    @Binding var selection: Value
    let title: (Value) -> String

    var body: some View {
        HStack(spacing: 0) {
            ForEach(values) { value in
                Button {
                    withAnimation(.snappy(duration: 0.2)) { selection = value }
                } label: {
                    Text(title(value))
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: Theme.minTapTarget)
                        .background {
                            if value == selection {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Theme.cardBackground)
                                    .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
                            }
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(value == selection ? [.isSelected, .isButton] : .isButton)
            }
        }
        .padding(4)
        .background(Theme.pillBackground, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

#Preview {
    @Previewable @State var selection = ScheduleSegment.friends
    return SegmentedTabs(values: ScheduleSegment.allCases, selection: $selection) { $0.rawValue }
        .padding()
        .background(Theme.screenBackground)
}
