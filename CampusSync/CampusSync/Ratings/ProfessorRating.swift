//
//  ProfessorRating.swift
//  CampusSync
//
//  A professor's rating from RateMyProfessors.com. These are real,
//  student-submitted numbers fetched from RateMyProfessors, not values invented
//  by the app, and the UI must credit the source. Kept apart from the frozen
//  `ProfessorInfo` model so no stored schema changes.
//

import Foundation

nonisolated struct ProfessorRating: Codable, Equatable, Sendable {
    var legacyID: Int
    var firstName: String
    var lastName: String
    var department: String?
    var overallRating: Double
    var difficulty: Double
    /// Percent, 0 to 100. Nil when RateMyProfessors has no data for it (it sends -1).
    var wouldTakeAgainPercent: Double?
    var numRatings: Int

    var displayName: String { "\(firstName) \(lastName)" }
    /// RateMyProfessors lists some people with zero ratings.
    var hasRatings: Bool { numRatings > 0 }

    var profileURL: URL? {
        URL(string: "https://www.ratemyprofessors.com/professor/\(legacyID)")
    }
}

nonisolated enum ProfessorRatingLookup: Equatable, Sendable {
    case found(ProfessorRating)
    /// RateMyProfessors has no matching professor at this school.
    case notFound
    /// Could not reach RateMyProfessors and nothing was cached.
    case unavailable
}

protocol ProfessorRatingProvider: Sendable {
    func rating(for instructor: String) async -> ProfessorRatingLookup
}

/// Picks the right professor out of RateMyProfessors' fuzzy search results.
nonisolated enum ProfessorNameMatcher {
    /// Lowercased, accents folded, punctuation dropped, whitespace collapsed.
    static func normalize(_ name: String) -> String {
        name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber || $0.isWhitespace || $0 == "-" }
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }

    /// Full-name match first. Failing that, same last name and same first given name
    /// ("Jun Myeong Choi" still finds "Jun Choi"). Ties go to the most-rated entry.
    static func bestMatch(for instructor: String, in teachers: [ProfessorRating]) -> ProfessorRating? {
        let tokens = normalize(instructor).split(separator: " ").map(String.init)
        guard let first = tokens.first, let last = tokens.last, tokens.count >= 2 else { return nil }
        let fullName = tokens.joined(separator: " ")

        let exact = teachers.filter { normalize($0.displayName) == fullName }
        if let best = exact.max(by: { $0.numRatings < $1.numRatings }) { return best }

        let loose = teachers.filter {
            let teacherFirst = normalize($0.firstName).split(separator: " ").first.map(String.init)
            return normalize($0.lastName).split(separator: " ").last.map(String.init) == last && teacherFirst == first
        }
        return loose.max(by: { $0.numRatings < $1.numRatings })
    }
}
