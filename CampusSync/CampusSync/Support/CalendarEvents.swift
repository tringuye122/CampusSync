//
//  CalendarEvents.swift
//  CampusSync
//
//  One-off events that show on the Timetable next to classes: events of clubs you joined and
//  invites you RSVP'd to. Pure functions; `now` always comes from AppClock.
//

import Foundation

struct CalendarEvent: Identifiable, Equatable {
    enum Kind: Equatable { case club, invite }

    var id: String
    var kind: Kind
    var title: String
    /// Where it is (the club's location, or the invite's landmark).
    var place: String
    var start: Date
    var end: Date
}

enum CalendarEvents {
    /// Club events for clubs you joined, and invites you said you are going to.
    static func build(
        clubEvents: [ClubEvent], joinedClubIDs: Set<String>,
        invites: [OpenInvite], rsvpedIDs: Set<String>
    ) -> [CalendarEvent] {
        let clubs = clubEvents.filter { joinedClubIDs.contains($0.clubID) }.map {
            CalendarEvent(id: "club-\($0.id)", kind: .club, title: $0.title, place: $0.location, start: $0.startTime, end: $0.endTime)
        }
        let plans = invites.filter { rsvpedIDs.contains($0.id) }.map {
            CalendarEvent(id: "invite-\($0.id)", kind: .invite, title: $0.title, place: $0.landmark.displayName, start: $0.startTime, end: $0.expiresAt)
        }
        return (clubs + plans).sorted { $0.start < $1.start }
    }

    /// The Monday of the week the timetable shows: this week Monday to Friday, or the coming
    /// week once it is the weekend (the same rule the day chips use to pick a day).
    static func displayedMonday(now: Date, calendar: Calendar = .current) -> Date {
        let weekday = calendar.component(.weekday, from: now)   // 1 Sun ... 7 Sat
        let startOfDay = calendar.startOfDay(for: now)
        let daysBack = weekday == 1 ? -1 : (weekday == 7 ? -2 : weekday - 2)   // Sun and Sat roll forward
        return calendar.date(byAdding: .day, value: -daysBack, to: startOfDay) ?? startOfDay
    }

    /// Events that fall on `day` of the displayed week.
    static func events(
        _ all: [CalendarEvent], on day: Weekday, now: Date, calendar: Calendar = .current
    ) -> [CalendarEvent] {
        let monday = displayedMonday(now: now, calendar: calendar)
        guard let date = calendar.date(byAdding: .day, value: day.rawValue - Weekday.mon.rawValue, to: monday)
        else { return [] }
        return all.filter { calendar.isDate($0.start, inSameDayAs: date) }
    }
}
