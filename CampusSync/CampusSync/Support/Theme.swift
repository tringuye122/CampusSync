//
//  Theme.swift
//  CampusSync
//
//  Design tokens. Colors come from the asset catalog (light and dark variants),
//  never hard-coded hex. Must be a member of both the app and widget targets,
//  so it must not reference model types.
//

import SwiftUI

enum Theme {
    // Carolina Blue #7BAFD4 is for fills and buttons. Use Navy / textPrimary for text,
    // since Carolina Blue text on white fails contrast.
    static let carolinaBlue = Color("CarolinaBlue")
    static let navy = Color("Navy")
    static let textPrimary = Color("TextPrimary")
    static let cardBackground = Color("CardBackground")
    static let screenBackground = Color("ScreenBackground")

    static let categoryFood = Color("CategoryFood")
    static let categoryStudy = Color("CategoryStudy")
    static let categoryFitness = Color("CategoryFitness")
    static let categorySocial = Color("CategorySocial")

    static let cardRadius: CGFloat = 20
    static let cardPadding: CGFloat = 16
    static let minTapTarget: CGFloat = 44
}

/// Shared card look: 20 pt radius, 16 pt padding.
struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(Theme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Theme.cardBackground,
                in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
            )
    }
}

extension View {
    func cardStyle() -> some View {
        modifier(CardStyle())
    }

    /// Guarantees the 44 pt minimum tap target.
    func minTapTarget() -> some View {
        frame(minWidth: Theme.minTapTarget, minHeight: Theme.minTapTarget)
    }
}
