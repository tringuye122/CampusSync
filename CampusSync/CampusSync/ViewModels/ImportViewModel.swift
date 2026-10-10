//
//  ImportViewModel.swift
//  CampusSync
//
//  Drives the PDF import flow: parse the picked file, let the student review and
//  fix the parsed classes, then save. Nothing is saved until `save` runs, and the
//  PDF itself is never copied or stored. The parsed text is never logged.
//

import Foundation
import Observation

@Observable
final class ImportViewModel {
    private(set) var drafts: [ImportedClass] = []
    private(set) var termLabel: String?
    private(set) var skipped: [String] = []
    private(set) var isParsing = false
    /// Presents the review sheet.
    var isReviewing = false
    var errorMessage: String?

    func importPDF(at url: URL, using importer: ScheduleImporter) async {
        isParsing = true
        defer { isParsing = false }
        do {
            let result = try await importer.importSchedule(from: url)
            guard !result.classes.isEmpty else {
                errorMessage = "No usable classes were found in that file. Every meeting had a TBA or unsupported time."
                return
            }
            drafts = result.classes
            termLabel = result.term
            skipped = result.skipped
            isReviewing = true
        } catch ImportError.noCoursesFound {
            errorMessage = "That doesn't look like a ConnectCarolina class schedule."
        } catch {
            errorMessage = "Couldn't read that PDF."
        }
    }

    func remove(_ draft: ImportedClass) {
        drafts.removeAll { $0.id == draft.id }
    }

    func update(_ draft: ImportedClass) {
        guard let index = drafts.firstIndex(where: { $0.id == draft.id }) else { return }
        drafts[index] = draft
    }

    var canSave: Bool { !drafts.isEmpty }

    /// Replaces the saved schedule with the reviewed classes, then refreshes the widget.
    /// Returns true on success.
    @discardableResult
    func save(services: AppServices) async -> Bool {
        // Ratings are fetched from RateMyProfessors on demand, not stored on the class.
        let classes = drafts.map { $0.makeClassSchedule(professor: nil) }
        do {
            try await services.schedule.replaceClasses(with: classes)
            await services.syncWidget()
            Task { await services.warmProfessorRatings() }
            isReviewing = false
            drafts = []
            return true
        } catch {
            errorMessage = "Couldn't save your schedule."
            return false
        }
    }

    func cancel() {
        isReviewing = false
        drafts = []
    }
}
