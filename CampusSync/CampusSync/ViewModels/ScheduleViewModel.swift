//
//  ScheduleViewModel.swift
//  CampusSync
//
//  Drives the Schedule tab. Talks only to ScheduleRepository and the pure
//  FreeSlotCalculator, never to SwiftData directly.
//

import Foundation
import Observation

@Observable
final class ScheduleViewModel {
    private(set) var classes: [ClassSchedule] = []
    private(set) var freeSlotsByDay: [Weekday: [FreeSlot]] = [:]
    private(set) var errorMessage: String?
    /// Set when a class block is tapped; presents the professor rating sheet.
    var selectedClass: ClassSchedule?

    let settings: FreeSlotSettings

    init(settings: FreeSlotSettings = .standard) {
        self.settings = settings
    }

    var isEmpty: Bool { classes.isEmpty }

    func load(from repository: ScheduleRepository) async {
        do {
            classes = try await repository.classes()
            let meetings = classes.map(\.meeting)
            freeSlotsByDay = Dictionary(uniqueKeysWithValues: Weekday.allCases.map {
                ($0, FreeSlotCalculator.freeSlots(on: $0, meetings: meetings, settings: settings))
            })
            errorMessage = nil
        } catch {
            errorMessage = "Couldn't load your schedule."
        }
    }

    func loadDemoSchedule(using repository: ScheduleRepository) async {
        do {
            try await repository.loadDemoSchedule()
            await load(from: repository)
        } catch {
            errorMessage = "Couldn't load the demo schedule."
        }
    }

    func classes(on day: Weekday) -> [ClassSchedule] {
        classes.filter { $0.weekdays.contains(day) }
    }

    func freeSlots(on day: Weekday) -> [FreeSlot] {
        freeSlotsByDay[day] ?? []
    }
}
