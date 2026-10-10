//
//  HomeViewModel.swift
//  CampusSync
//
//  Drives the Home tab. Phase 3 supplies the class meetings for the Live Status
//  banner; Phase 4 adds the invites carousel.
//

import Foundation
import Observation

@Observable
final class HomeViewModel {
    private(set) var meetings: [SnapshotMeeting] = []

    func load(schedule: ScheduleRepository) async {
        meetings = ((try? await schedule.classes()) ?? []).flatMap(\.snapshotMeetings)
    }
}
