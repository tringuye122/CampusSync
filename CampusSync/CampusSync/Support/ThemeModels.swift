//
//  ThemeModels.swift
//  CampusSync
//
//  App-only styling for model enums. Kept apart from Theme.swift so the widget
//  target does not need the models.
//

import SwiftUI

extension InviteCategory {
    var color: Color {
        switch self {
        case .food: Theme.categoryFood
        case .study: Theme.categoryStudy
        case .fitness: Theme.categoryFitness
        case .social: Theme.categorySocial
        }
    }
}

extension ClubAccess {
    var color: Color {
        switch self {
        case .public: Theme.carolinaBlue
        case .membersOnly: Theme.navy
        case .duesRequired: Theme.categoryFood
        }
    }
}
