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
    /// RateMyProfessors results by first-listed instructor, filled by `loadRatings`.
    private(set) var ratings: [String: ProfessorRatingLookup] = [:]

    /// Joined clubs' events and RSVP'd invites, drawn on the timetable beside classes.
    private(set) var calendarEvents: [CalendarEvent] = []

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

    /// Events of clubs I joined and invites I RSVP'd to. A failure just leaves the timetable with classes only.
    func loadEvents(services: AppServices, now: Date) async {
        guard let user = try? await services.users.currentUser() else { calendarEvents = []; return }
        let clubEvents = (try? await services.clubs.events(now: now)) ?? []
        let invites = (try? await services.invites.activeInvites(now: now)) ?? []
        calendarEvents = CalendarEvents.build(
            clubEvents: clubEvents, joinedClubIDs: Set(user.joinedClubIDs),
            invites: invites, rsvpedIDs: Set(user.rsvpedInviteIDs))
    }

    func events(on day: Weekday, now: Date) -> [CalendarEvent] {
        CalendarEvents.events(calendarEvents, on: day, now: now)
    }

    /// Looks up every first-listed instructor, a few at a time. Results are cached on disk by the
    /// repository, so this is cheap after the first run and still works offline.
    func loadRatings(from repository: ScheduleRepository) async {
        let names = Set(classes.compactMap(\.primaryInstructor))
        await withTaskGroup(of: (String, ProfessorRatingLookup).self) { group in
            for name in names where ratings[name] == nil {
                group.addTask { @MainActor in (name, await repository.professorRating(for: name)) }
            }
            for await (name, lookup) in group { ratings[name] = lookup }
        }
    }

    /// nil while the lookup has not finished.
    func rating(for cls: ClassSchedule) -> ProfessorRatingLookup? {
        cls.primaryInstructor.flatMap { ratings[$0] }
    }

    func loadDemoSchedule(using services: AppServices) async {
        do {
            try await services.schedule.loadDemoSchedule()
            await load(from: services.schedule)
            await services.syncWidget()
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
