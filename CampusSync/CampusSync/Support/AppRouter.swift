//
//  AppRouter.swift
//  CampusSync
//
//  Owns the selected tab so a widget tap can jump to the right one.
//  Deep links look like campussync://schedule or campussync://invites.
//

import Foundation
import Observation

@Observable
final class AppRouter {
    var selectedTab: AppTab = .home

    static let scheme = "campussync"

    func open(_ url: URL) {
        guard url.scheme == Self.scheme,
              let host = url.host,
              let tab = AppTab(rawValue: host)
        else { return }
        selectedTab = tab
    }
}
