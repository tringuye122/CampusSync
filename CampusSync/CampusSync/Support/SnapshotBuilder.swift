//
//  SnapshotBuilder.swift
//  CampusSync
//
//  Turns app state into the WidgetSnapshot the widget reads. Pure; the caller
//  saves it and reloads timelines (see AppServices.syncWidget).
//

import Foundation

enum SnapshotBuilder {
    /// The widget shows at most this many invites.
    static let maxInvites = 5

    static func make(
        classes: [ClassSchedule],
        invites: [OpenInvite],
        now: Date,
        clockOffset: TimeInterval
    ) -> WidgetSnapshot {
        let activeInvites = invites
            .filter { !$0.isExpired(at: now) }
            .sorted { $0.startTime < $1.startTime }
            .prefix(maxInvites)
            .map {
                SnapshotInvite(
                    id: $0.id,
                    title: $0.title,
                    landmarkName: $0.landmark.displayName,
                    landmarkSymbol: $0.landmark.symbol,
                    startTime: $0.startTime,
                    expiresAt: $0.expiresAt
                )
            }

        return WidgetSnapshot(
            version: WidgetSnapshot.currentVersion,
            generatedAt: now,
            clockOffset: clockOffset,
            meetings: classes.flatMap(\.snapshotMeetings),
            invites: Array(activeInvites)
        )
    }
}
