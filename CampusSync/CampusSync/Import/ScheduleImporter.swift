//
//  ScheduleImporter.swift
//  CampusSync
//
//  Common shape for schedule importers: ConnectCarolinaPDFParser (primary) and
//  ICSParser (stretch). Importers return plain values; nothing is saved until
//  the student confirms on the review screen.
//
//  Privacy: the real PDF header carries the student's name and university ID.
//  Importers read only the term and the course cards, and must never store,
//  log or return anything else.
//

import Foundation
import UniformTypeIdentifiers

/// One meeting pattern of a course, before it becomes a saved `ClassSchedule`.
/// A plain value so the review screen can edit it freely.
struct ImportedClass: Identifiable, Equatable, Sendable {
    var id = UUID()
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
    /// As listed; the first name is the primary professor.
    var instructors: [String]

    var primaryInstructor: String? { instructors.first }

    func makeClassSchedule(professor: ProfessorInfo?) -> ClassSchedule {
        ClassSchedule(
            courseCode: courseCode, title: title, section: section, units: units,
            weekdays: weekdays, startMinutes: startMinutes, endMinutes: endMinutes,
            building: building, room: room, startDate: startDate, endDate: endDate,
            instructors: instructors, professor: professor)
    }
}

struct ImportResult: Equatable, Sendable {
    /// e.g. "2026 Fall". Nil when the file has no term line.
    var term: String?
    var classes: [ImportedClass]
    /// Meetings that were left out (TBA times, unsupported days), as short readable notes.
    var skipped: [String]
}

enum ImportError: Error, Equatable {
    /// The file could not be opened or contained no readable text.
    case unreadableFile
    /// Text was found but no course cards were recognised.
    case noCoursesFound
}

protocol ScheduleImporter {
    /// File types this importer accepts, for the file picker.
    var supportedTypes: [UTType] { get }
    func importSchedule(from url: URL) async throws -> ImportResult
}
