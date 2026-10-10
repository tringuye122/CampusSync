//
//  AccountStore.swift
//  CampusSync
//
//  Ties the on-device cache to the signed-in student. The seeded demo data is for
//  previews, tests and the signed-out fallback; a real account starts from an empty
//  cache. Sign-out wipes what came from the server (friends' schedules, invites, clubs),
//  but keeps the student's OWN imported classes: course titles and instructors exist only
//  on this device (the rules forbid them in Firestore), so wiping them would force a
//  re-import at every sign-in. They are kept only for the same account.
//

import Foundation
import SwiftData

/// Which account the cached `ClassSchedule` rows belong to.
enum ScheduleOwner {
    private static let key = "scheduleOwnerUID"

    static var uid: String? {
        get { UserDefaults.standard.string(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}

extension LocalDataStore {
    /// Makes the cache belong to `account`. A different (or seeded demo) user's data is
    /// removed first, except this account's own classes if they were kept at sign-out.
    /// Returns true if the cache was reset. Safe to call on every launch.
    @discardableResult
    func adoptAccount(_ account: UserAccount) throws -> Bool {
        if let existing = try context.fetch(FetchDescriptor<UserProfile>()).first, existing.id == account.uid {
            existing.displayName = account.displayName
            existing.handle = account.handle
            try context.save()
            return false
        }
        // Keep the student's own classes only if the cache is theirs from an earlier session. The
        // fictional demo cache (seed user) never counts, whatever the owner flag says.
        let hasSeedUser = try context.fetch(FetchDescriptor<UserProfile>()).contains { $0.id.hasPrefix("seed-") }
        try wipe(keepingSchedule: ScheduleOwner.uid == account.uid && !hasSeedUser)
        ScheduleOwner.uid = account.uid
        context.insert(UserProfile(id: account.uid, displayName: account.displayName, handle: account.handle))
        try context.save()
        return true
    }

    /// Removes every cached row. With `keepingSchedule`, the student's own classes stay.
    func wipe(keepingSchedule: Bool = false) throws {
        try context.delete(model: UserProfile.self)
        if !keepingSchedule {
            try context.delete(model: ClassSchedule.self)
        }
        try context.delete(model: FriendProfile.self)
        try context.delete(model: OpenInvite.self)
        try context.delete(model: Club.self)
        try context.delete(model: ClubEvent.self)
        try context.save()
    }
}
