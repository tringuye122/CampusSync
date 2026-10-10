//
//  FilterChips.swift
//  CampusSync
//
//  Row of filter chips from the designs. `.hugging` chips size to their text and scroll sideways
//  (Invites categories); `.equalWidth` chips share the row (Clubs: All clubs / Free for me / Joined).
//

import SwiftUI

struct FilterChips<Value: Hashable & Identifiable>: View {
    enum Layout { case hugging, equalWidth }

    let values: [Value]
    @Binding var selection: Value
    var layout: Layout = .hugging
    let title: (Value) -> String

    var body: some View {
        switch layout {
        case .hugging:
            ScrollView(.horizontal, showsIndicators: false) { row.padding(.horizontal, 16) }
        case .equalWidth:
            row.padding(.horizontal, 16)
        }
    }

    private var row: some View {
        HStack(spacing: 10) {
            ForEach(values) { value in
                let isSelected = value == selection
                Button { withAnimation(.snappy(duration: 0.2)) { selection = value } } label: {
                    Text(title(value))
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, layout == .hugging ? 20 : 8)
                        .frame(maxWidth: layout == .equalWidth ? .infinity : nil, minHeight: Theme.minTapTarget + 8)
                        .background(
                            isSelected ? Theme.carolinaBlue : Theme.cardBackground,
                            in: Capsule())
                        .foregroundStyle(isSelected ? Theme.navy : Theme.textPrimary)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
            }
        }
    }
}

#Preview {
    @Previewable @State var category: InviteFilter = .all
    FilterChips(values: InviteFilter.allCases, selection: $category) { $0.title }
        .padding(.vertical)
        .background(Theme.screenBackground)
}
