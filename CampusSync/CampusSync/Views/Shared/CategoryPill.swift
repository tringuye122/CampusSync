//
//  CategoryPill.swift
//  CampusSync
//
//  Category tag. Color is never the only signal: the SF Symbol and the name
//  always accompany it.
//

import SwiftUI

struct CategoryPill: View {
    let category: InviteCategory
    var isSelected = false

    var body: some View {
        Label(category.displayName, systemImage: category.symbol)
            .labelStyle(.titleAndIcon)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(minHeight: Theme.minTapTarget - 8)
            .background(category.color.opacity(isSelected ? 0.35 : 0.18), in: Capsule())
            .overlay(Capsule().strokeBorder(category.color, lineWidth: isSelected ? 2 : 0))
    }
}

#Preview {
    VStack(spacing: 12) {
        ForEach(InviteCategory.allCases) { CategoryPill(category: $0) }
        CategoryPill(category: .food, isSelected: true)
    }
    .padding()
}
