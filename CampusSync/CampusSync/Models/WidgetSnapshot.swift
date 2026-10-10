//
//  WidgetSnapshot.swift
//  CampusSync
//
//  FROZEN after Phase 1 except for additive fields. Announce any change.
//
//  The only thing the widget reads. The app writes it to the App Group and calls
//  WidgetCenter.shared.reloadAllTimelines(). It deliberately uses plain values
//  (no SwiftData, no model enums) so the widget target needs no other model code.
//  Must be a member of both the app and widget targets.
//

import Foundation

nonisolated struct WidgetSnapshot: Codable, Equatable {
    /// Bump when the shape changes incompatibly; mismatches decode as nil (empty state).
    static let currentVersion = 1

    var version: Int
    var generatedAt: Date
    /// Demo time override in seconds, so the widget agrees with the app's AppClock.
    var clockOffset: TimeInterval
    /// The whole weekly class pattern, so the widget can pre-build timeline entries
    /// at every class start and end without the app running.
    var meetings: [SnapshotMeeting]
    /// Active invites (up to 5), soonest first.
    var invites: [SnapshotInvite]

    static let empty = WidgetSnapshot(
        version: currentVersion,
        generatedAt: .distantPast,
        clockOffset: 0,
        meetings: [],
        invites: []
    )
}

nonisolated struct SnapshotMeeting: Codable, Equatable {
    var courseCode: String
    /// Preformatted, e.g. "Sitterson Hall FB009".
    var location: String
    /// Calendar weekday number, Monday = 2 ... Friday = 6.
    var weekday: Int
    var startMinutes: Int
    var endMinutes: Int
}

nonisolated struct SnapshotInvite: Codable, Equatable {
    var id: String
    var title: String
    var landmarkName: String
    var landmarkSymbol: String
    var startTime: Date
    var expiresAt: Date
}

// MARK: - Encoding

nonisolated extension WidgetSnapshot {
    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    func encoded() throws -> Data {
        try Self.encoder.encode(self)
    }

    /// Nil on missing data, corrupt JSON, or a version mismatch.
    static func decode(_ data: Data?) -> WidgetSnapshot? {
        guard let data,
              let snapshot = try? decoder.decode(WidgetSnapshot.self, from: data),
              snapshot.version == currentVersion
        else { return nil }
        return snapshot
    }

    /// Fail-safe read for the widget: any problem yields the empty state.
    static func load() -> WidgetSnapshot {
        decode(AppGroupManager.readSnapshotData()) ?? .empty
    }

    /// Writes to the App Group. The caller reloads widget timelines afterward.
    @discardableResult
    func save() -> Bool {
        guard let data = try? encoded() else { return false }
        return AppGroupManager.writeSnapshotData(data)
    }
}
