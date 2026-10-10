//
//  AppGroupManager.swift
//  CampusSync
//
//  Single place that knows about the App Group container. The app writes the
//  widget snapshot here; the widget only reads it. Must be a member of both
//  the app and widget targets.
//

import Foundation

// The app target defaults to MainActor isolation; the widget provider reads
// this off the main actor, so opt out explicitly.
nonisolated enum AppGroupManager {
    /// Must match the App Group in both targets' entitlements.
    static let groupID = "group.Tri-Nguyen.CampusSync"

    /// File name of the JSON snapshot inside the container.
    static let snapshotFileName = "widget-snapshot.json"

    /// Nil when the App Group capability is missing or misconfigured.
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)
    }

    static var snapshotURL: URL? {
        containerURL?.appendingPathComponent(snapshotFileName)
    }

    /// Atomically writes snapshot bytes. Returns false if the container is unavailable.
    @discardableResult
    static func writeSnapshotData(_ data: Data) -> Bool {
        guard let url = snapshotURL else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Nil when the container or file is missing; callers show an empty state.
    static func readSnapshotData() -> Data? {
        guard let url = snapshotURL else { return nil }
        return try? Data(contentsOf: url)
    }
}
