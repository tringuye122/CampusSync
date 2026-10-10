//
//  InviteFilter.swift
//  CampusSync
//
//  The category chips on the Invites tab: All, then one per category.
//

import Foundation

enum InviteFilter: Hashable, Identifiable, CaseIterable {
    case all
    case category(InviteCategory)

    static var allCases: [InviteFilter] { [.all] + InviteCategory.allCases.map(InviteFilter.category) }

    var id: String {
        switch self {
        case .all: "all"
        case .category(let category): category.rawValue
        }
    }

    var title: String {
        switch self {
        case .all: "All"
        case .category(let category): category.displayName
        }
    }

    func includes(_ invite: OpenInvite) -> Bool {
        switch self {
        case .all: true
        case .category(let category): invite.category == category
        }
    }
}
