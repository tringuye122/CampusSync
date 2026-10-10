//
//  Models.swift
//  CampusSync
//
//  FROZEN after Phase 1 except for additive fields. Announce any change.
//
//  Times of day are stored as minutes after midnight plus a weekday, so a class
//  repeats every week with no date math. One-off things (invites, club events)
//  use absolute Dates.
//

import Foundation
import SwiftData

// MARK: - Enums

/// Monday...Friday only; matches Calendar's weekday numbering (Sunday = 1).
/// There are no Saturday classes, so importers skip anything else.
enum Weekday: Int, Codable, CaseIterable, Identifiable {
    case mon = 2, tue, wed, thu, fri

    var id: Int { rawValue }

    /// Two-letter token used by the ConnectCarolina PDF ("MoWe", "TuTh").
    var token: String {
        switch self {
        case .mon: "Mo"
        case .tue: "Tu"
        case .wed: "We"
        case .thu: "Th"
        case .fri: "Fr"
        }
    }

    var shortLabel: String {
        switch self {
        case .mon: "Mon"
        case .tue: "Tue"
        case .wed: "Wed"
        case .thu: "Thu"
        case .fri: "Fri"
        }
    }

    var fullName: String {
        switch self {
        case .mon: "Monday"
        case .tue: "Tuesday"
        case .wed: "Wednesday"
        case .thu: "Thursday"
        case .fri: "Friday"
        }
    }

    init?(token: String) {
        guard let match = Weekday.allCases.first(where: { $0.token == token }) else { return nil }
        self = match
    }
}

enum InviteCategory: String, Codable, CaseIterable, Identifiable {
    case food, study, fitness, social

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .food: "Food"
        case .study: "Study"
        case .fitness: "Fitness"
        case .social: "Social"
        }
    }

    /// Pills always pair color with this symbol so color is never the only signal.
    var symbol: String {
        switch self {
        case .food: "fork.knife"
        case .study: "book.fill"
        case .fitness: "figure.run"
        case .social: "person.3.fill"
        }
    }
}

enum ClubAccess: String, Codable, CaseIterable, Identifiable {
    case `public`, membersOnly, duesRequired

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .public: "Public"
        case .membersOnly: "Members Only"
        case .duesRequired: "Dues Required"
        }
    }

    var symbol: String {
        switch self {
        case .public: "globe"
        case .membersOnly: "lock.fill"
        case .duesRequired: "dollarsign.circle.fill"
        }
    }
}

/// "Nearby" means tagged to one of these. No Core Location.
enum Landmark: String, Codable, CaseIterable, Identifiable {
    case thePit, chaseDiningHall, davisLibrary, studentUnion, polkPlace, woollenGym

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .thePit: "The Pit"
        case .chaseDiningHall: "Chase Dining Hall"
        case .davisLibrary: "Davis Library"
        case .studentUnion: "Student Union"
        case .polkPlace: "Polk Place"
        case .woollenGym: "Woollen Gym"
        }
    }

    var symbol: String {
        switch self {
        case .thePit: "person.3"
        case .chaseDiningHall: "fork.knife"
        case .davisLibrary: "books.vertical"
        case .studentUnion: "cup.and.saucer"
        case .polkPlace: "tree"
        case .woollenGym: "dumbbell"
        }
    }
}

// MARK: - Plain structs (Codable, not tables)

/// Mock scores only. Kept out of SwiftData so changing them never needs a migration.
/// Always shown with a visible "Demo data" footer.
struct ProfessorInfo: Codable, Hashable {
    var name: String
    var overallRating: Double
    var difficulty: Double
    var wouldTakeAgainPercent: Int
    var topTags: [String]
}

/// A friend's class time. Friends only need times for overlap, so no titles are stored.
struct ClassMeeting: Codable, Hashable {
    var courseCode: String
    var weekdays: [Weekday]
    var startMinutes: Int
    var endMinutes: Int
    var building: String
}

/// Computed, never persisted. Used by the timetable and the overlap view.
struct FreeSlot: Identifiable, Hashable {
    var id = UUID()
    var weekday: Weekday
    var startMinutes: Int
    var endMinutes: Int
    var label: String

    var durationMinutes: Int { endMinutes - startMinutes }
}

// MARK: - SwiftData models

@Model
final class UserProfile {
    @Attribute(.unique) var id: UUID
    var displayName: String
    var handle: String
    /// The friend graph. Comes from seed data in the MVP.
    var friendIDs: [UUID]
    /// Clubs the user joined or subscribed to (they are notified about these).
    var joinedClubIDs: [UUID]
    var rsvpedInviteIDs: [UUID]
    /// One flag for the whole profile, as in the spec. If we ever need per-club
    /// dues, add a separate `duesPaidClubIDs` list rather than changing this.
    var isVerifiedMember: Bool

    init(
        id: UUID = UUID(),
        displayName: String,
        handle: String,
        friendIDs: [UUID] = [],
        joinedClubIDs: [UUID] = [],
        rsvpedInviteIDs: [UUID] = [],
        isVerifiedMember: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.handle = handle
        self.friendIDs = friendIDs
        self.joinedClubIDs = joinedClubIDs
        self.rsvpedInviteIDs = rsvpedInviteIDs
        self.isVerifiedMember = isVerifiedMember
    }
}

/// One row per meeting pattern, so a course with several meeting rows in the PDF
/// produces several rows sharing a `courseCode`.
@Model
final class ClassSchedule {
    @Attribute(.unique) var id: UUID
    var courseCode: String
    var title: String
    var section: String
    var units: Double
    var weekdays: [Weekday]
    var startMinutes: Int
    var endMinutes: Int
    var building: String
    var room: String
    var startDate: Date
    var endDate: Date
    /// As listed in the PDF; the first name is the primary professor.
    var instructors: [String]
    var professor: ProfessorInfo?

    var primaryInstructor: String? { instructors.first }

    var meeting: ClassMeeting {
        ClassMeeting(
            courseCode: courseCode,
            weekdays: weekdays,
            startMinutes: startMinutes,
            endMinutes: endMinutes,
            building: building
        )
    }

    init(
        id: UUID = UUID(),
        courseCode: String,
        title: String,
        section: String,
        units: Double,
        weekdays: [Weekday],
        startMinutes: Int,
        endMinutes: Int,
        building: String,
        room: String,
        startDate: Date,
        endDate: Date,
        instructors: [String],
        professor: ProfessorInfo? = nil
    ) {
        self.id = id
        self.courseCode = courseCode
        self.title = title
        self.section = section
        self.units = units
        self.weekdays = weekdays
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.building = building
        self.room = room
        self.startDate = startDate
        self.endDate = endDate
        self.instructors = instructors
        self.professor = professor
    }
}

@Model
final class FriendProfile {
    @Attribute(.unique) var id: UUID
    var displayName: String
    var classes: [ClassMeeting]

    init(id: UUID = UUID(), displayName: String, classes: [ClassMeeting]) {
        self.id = id
        self.displayName = displayName
        self.classes = classes
    }
}

/// A time-boxed plan sent only to friends the host picked (`recipientIDs`).
@Model
final class OpenInvite {
    @Attribute(.unique) var id: UUID
    var title: String
    var landmark: Landmark
    var category: InviteCategory
    var startTime: Date
    /// Absolute date (not a duration) so the widget can evaluate it without the app running.
    var expiresAt: Date
    var hostID: UUID
    var hostName: String
    var attendeeIDs: [UUID]
    /// Friends the host chose to invite.
    var recipientIDs: [UUID]
    var capacity: Int

    /// Expired when now > expiresAt. Always filtered at read time.
    func isExpired(at now: Date) -> Bool { now > expiresAt }

    init(
        id: UUID = UUID(),
        title: String,
        landmark: Landmark,
        category: InviteCategory,
        startTime: Date,
        expiresAt: Date,
        hostID: UUID,
        hostName: String,
        attendeeIDs: [UUID] = [],
        recipientIDs: [UUID] = [],
        capacity: Int = 8
    ) {
        self.id = id
        self.title = title
        self.landmark = landmark
        self.category = category
        self.startTime = startTime
        self.expiresAt = expiresAt
        self.hostID = hostID
        self.hostName = hostName
        self.attendeeIDs = attendeeIDs
        self.recipientIDs = recipientIDs
        self.capacity = capacity
    }
}

@Model
final class Club {
    @Attribute(.unique) var id: UUID
    var name: String
    var summary: String
    var symbol: String
    var access: ClubAccess
    /// Whole dollars; there are no real payments.
    var duesAmount: Int

    init(
        id: UUID = UUID(),
        name: String,
        summary: String,
        symbol: String,
        access: ClubAccess,
        duesAmount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.symbol = symbol
        self.access = access
        self.duesAmount = duesAmount
    }
}

/// Club events are public; people who joined or subscribed to the club are notified.
@Model
final class ClubEvent {
    @Attribute(.unique) var id: UUID
    var clubID: UUID
    var clubName: String
    var title: String
    var details: String
    var location: String
    var startTime: Date
    var access: ClubAccess
    /// Whole dollars.
    var duesAmount: Int

    init(
        id: UUID = UUID(),
        clubID: UUID,
        clubName: String,
        title: String,
        details: String,
        location: String,
        startTime: Date,
        access: ClubAccess,
        duesAmount: Int = 0
    ) {
        self.id = id
        self.clubID = clubID
        self.clubName = clubName
        self.title = title
        self.details = details
        self.location = location
        self.startTime = startTime
        self.access = access
        self.duesAmount = duesAmount
    }
}

enum AppSchema {
    static let models: [any PersistentModel.Type] = [
        UserProfile.self, ClassSchedule.self, FriendProfile.self,
        OpenInvite.self, Club.self, ClubEvent.self,
    ]
}

// MARK: - Time formatting

extension Int {
    /// Minutes after midnight rendered as "1:25 PM".
    var clockString: String {
        let hour24 = (self / 60) % 24
        let minute = self % 60
        let hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12
        return String(format: "%d:%02d %@", hour12, minute, hour24 < 12 ? "AM" : "PM")
    }
}
