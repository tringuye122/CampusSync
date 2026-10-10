//
//  ScheduleSharingSetting.swift
//  CampusSync
//
//  The on/off switch for sharing class times with friends. Just a per-device flag, with no
//  Firebase in it, so the local repositories and previews can use it too. Publishing the
//  times (or removing them) is the Firestore repository's job.
//

import Foundation

enum ScheduleSharingSetting {
    private static let key = "shareScheduleWithFriends"

    /// On by default; the student can switch it off in Account.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }

    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: key)
    }
}
