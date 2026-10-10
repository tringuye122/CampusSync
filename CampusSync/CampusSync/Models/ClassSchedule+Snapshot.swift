//
//  ClassSchedule+Snapshot.swift
//  CampusSync
//
//  Additive helper (Models.swift stays frozen): flattens a class into one
//  SnapshotMeeting per weekday, the shape the status engine and widget use.
//

import Foundation

extension ClassSchedule {
    var snapshotMeetings: [SnapshotMeeting] {
        weekdays.map {
            SnapshotMeeting(
                courseCode: courseCode,
                location: "\(building) \(room)",
                weekday: $0.rawValue,
                startMinutes: startMinutes,
                endMinutes: endMinutes
            )
        }
    }
}
