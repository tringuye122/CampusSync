//
//  RatingStyle.swift
//  CampusSync
//
//  How an inline rating is judged on the Classes cards. Pure, so the thresholds are tested.
//  The ratings themselves come from RateMyProfessors; this only decides colors and warnings.
//

import Foundation

enum RatingTone: Equatable {
    case good, fair, poor
}

enum RatingStyle {
    /// Ratings at or above this are green, below `fairThreshold` red, in between amber.
    static let goodThreshold = 4.0
    static let fairThreshold = 3.0
    /// With fewer ratings than this the average is shaky, so the card says "Low count".
    static let lowCountThreshold = 5

    static func tone(for rating: Double) -> RatingTone {
        if rating >= goodThreshold { return .good }
        return rating >= fairThreshold ? .fair : .poor
    }

    static func isLowCount(_ numRatings: Int) -> Bool { numRatings < lowCountThreshold }

    /// "4.3 / 5", "5 / 5": one decimal, dropping a trailing ".0".
    static func ratingText(_ rating: Double) -> String {
        let text = String(format: "%.1f", rating)
        return (text.hasSuffix(".0") ? String(text.dropLast(2)) : text) + " / 5"
    }

    /// "3.8", "2.5", "4": one decimal, dropping a trailing ".0".
    static func decimalText(_ value: Double) -> String {
        let text = String(format: "%.1f", value)
        return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
    }

    static func percentText(_ percent: Double?) -> String {
        percent.map { "\(Int($0.rounded()))%" } ?? "–"
    }
}
