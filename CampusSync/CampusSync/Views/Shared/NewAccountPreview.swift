//
//  NewAccountPreview.swift
//  CampusSync
//
//  One preview of the whole app for a brand-new account (no classes, friends, invites or clubs),
//  to check every empty state. Change `tab` and `segment` to look at another screen.
//

import SwiftUI

#Preview("New account") {
    let tab = AppTab.home
    let segment = ScheduleSegment.timetable
    let router = AppRouter()
    router.selectedTab = tab
    router.scheduleSegment = segment
    let backend = MockAuthBackend(signedInEmail: "justin@unc.edu")
    backend.seed(email: "justin@unc.edu", password: "password1", displayName: "Justin Nguyen", handle: "justin")
    let auth = AuthService(backend: backend, defaults: UserDefaults(suiteName: "preview-new-account")!)
    return MainTabView()
        .environment(AppServices.previewEmpty())
        .environment(AppClock())
        .environment(router)
        .environment(auth)
        .task { await auth.refresh() }
}
