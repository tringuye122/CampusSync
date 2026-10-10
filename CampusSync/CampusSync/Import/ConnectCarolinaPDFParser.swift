//
//  ConnectCarolinaPDFParser.swift
//  CampusSync
//
//  Parses the ConnectCarolina class-schedule PDF. Written against the real
//  PDFKit output of the sample file, which looks like this per course:
//
//      COMP 433
//      Section: 001
//      Description: MOBILE COMPUTING SYST
//      Wait List Position: -
//      Units: 3
//      Instructor: Shahriar Nirjon, Louie Lu, Tarik Reza
//      Toha, Zhenyu Wang                      <- wrapped continuation line
//      Days: TuTh
//      Start: 11:00 AM
//      End: 12:15 PM
//      Room: Sitterson Hall (inc-Rm SN014     <- truncated; other rooms look like "Fetzer Hall-Rm 0109"
//      Dates: 08/17 - 12/11
//
//  and each page has chrome that must go: a timestamp line at the top
//  ("10/10/26, 10:28 AM Schedule") and, at the bottom, a wrapped footer URL
//  followed by junk lines and a "Main 1/2_" counter.
//
//  Privacy: the header above the first course holds the student's name and ID.
//  Only the "Term:" line from that header is read; everything else is discarded
//  and nothing is logged.
//

import Foundation
import UniformTypeIdentifiers

nonisolated struct ConnectCarolinaPDFParser: ScheduleImporter {
    /// The Dates field has no year, so it comes from the header term. This is
    /// only used if the term line is missing.
    var fallbackYear: Int
    var calendar: Calendar = .current

    var supportedTypes: [UTType] { [.pdf] }

    func importSchedule(from url: URL) async throws -> ImportResult {
        try parse(pages: PDFTextExtractor.pages(from: url))
    }

    // MARK: Parsing

    /// Strips page chrome from each page, then concatenates, because a course card
    /// can be split across a page break (COMP 577 starts page 2 in the sample).
    func parse(pages: [String]) throws -> ImportResult {
        let lines = pages.flatMap(Self.cleanPage)
        guard let firstCourse = lines.firstIndex(where: Self.isCourseHeading) else {
            throw lines.isEmpty ? ImportError.unreadableFile : ImportError.noCoursesFound
        }

        let term = Self.parseTerm(from: lines[..<firstCourse])
        let year = term?.year ?? fallbackYear

        var blocks: [(code: String, lines: [String])] = []
        for line in lines[firstCourse...] {
            if Self.isCourseHeading(line) {
                blocks.append((line, []))
            } else {
                blocks[blocks.count - 1].lines.append(line)
            }
        }

        var classes: [ImportedClass] = []
        var skipped: [String] = []
        for block in blocks {
            let parsed = parseBlock(code: block.code, lines: block.lines, year: year)
            classes += parsed.classes
            skipped += parsed.skipped
        }
        return ImportResult(term: term?.label, classes: classes, skipped: skipped)
    }

    /// Drops chrome from one page. Everything from the footer URL to the end of the
    /// page is chrome (the URL wraps into junk lines like "HCX", "GN.H", "_").
    static func cleanPage(_ page: String) -> [String] {
        var result: [String] = []
        for raw in page.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("http://") || line.hasPrefix("https://") { break }
            if line.isEmpty { continue }
            // "10/10/26, 10:28 AM Schedule"
            if matches(#"^\d{1,2}/\d{1,2}/\d{2,4},\s+\d{1,2}:\d{2}\s*[AP]M\b"#, line) { continue }
            // "Main 1/2_" or "1/2"
            if matches(#"^(Main\s+)?\d+\s*/\s*\d+_?$"#, line) { continue }
            result.append(line)
        }
        return result
    }

    /// A course heading alone on its line, e.g. "COMP 523" or "LING 460".
    static func isCourseHeading(_ line: String) -> Bool {
        matches(#"^[A-Z]{3,4}\s\d{3}[A-Z]?$"#, line)
    }

    /// Reads "Term: 2026 Fall" from the header lines and ignores every other header line.
    static func parseTerm<S: Sequence>(from header: S) -> (year: Int, label: String)? where S.Element == String {
        for line in header {
            guard let groups = captures(#"Term:\s*(\d{4})\s+([A-Za-z]+)"#, in: line),
                  let year = Int(groups[0])
            else { continue }
            return (year, "\(groups[0]) \(groups[1])")
        }
        return nil
    }

    // MARK: Course blocks

    private static let knownLabels = [
        "Section", "Description", "Wait List Position", "Units", "Instructor",
        "Days", "Start", "End", "Room", "Dates",
    ]

    private func parseBlock(code: String, lines: [String], year: Int) -> (classes: [ImportedClass], skipped: [String]) {
        let fields = Self.fields(in: lines)
        func first(_ label: String) -> String? { fields.first { $0.label == label }?.value }
        func all(_ label: String) -> [String] { fields.filter { $0.label == label }.map(\.value) }

        let days = all("Days")
        guard !days.isEmpty else { return ([], ["\(code): no meeting days"]) }

        let section = first("Section") ?? ""
        let units = first("Units").flatMap(Double.init) ?? 0
        let title = CourseTitleFormatter.format(first("Description") ?? code)
        // The wrapped list was rejoined with spaces in `fields`, so splitting on commas is safe.
        let instructors = (first("Instructor") ?? "")
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0 != "-" }

        let starts = all("Start"), ends = all("End"), rooms = all("Room"), dates = all("Dates")

        var classes: [ImportedClass] = []
        var skipped: [String] = []
        for (index, rawDays) in days.enumerated() {
            // Meeting rows line up by position; a missing one falls back to the first.
            func pick(_ values: [String]) -> String? { index < values.count ? values[index] : values.first }

            let weekdays = Self.parseDays(rawDays)
            guard !weekdays.isEmpty,
                  let start = pick(starts).flatMap(Self.parseMinutes),
                  let end = pick(ends).flatMap(Self.parseMinutes),
                  end > start
            else {
                // TBA, online, Saturday or otherwise unusable: skip, and tell the student.
                skipped.append("\(code): \(rawDays) has no usable time")
                continue
            }

            let location = Self.parseRoom(pick(rooms) ?? "")
            let range = Self.parseDates(pick(dates) ?? "", year: year, calendar: calendar)
            classes.append(ImportedClass(
                courseCode: code, title: title, section: section, units: units,
                weekdays: weekdays, startMinutes: start, endMinutes: end,
                building: location.building, room: location.room,
                startDate: range.start, endDate: range.end, instructors: instructors))
        }
        return (classes, skipped)
    }

    /// Extracts every "Label: value" pair, in any order. A value runs up to the next
    /// known label, so wrapped lines and two-column text extraction both work.
    private static func fields(in lines: [String]) -> [(label: String, value: String)] {
        let text = lines.joined(separator: " ")
        let pattern = "(?<![A-Za-z])(" + knownLabels.joined(separator: "|") + "):"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let nsText = text as NSString
        let found = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        return found.enumerated().map { index, match in
            let label = nsText.substring(with: match.range(at: 1))
            let valueStart = match.range.location + match.range.length
            let valueEnd = index + 1 < found.count ? found[index + 1].range.location : nsText.length
            let raw = nsText.substring(with: NSRange(location: valueStart, length: valueEnd - valueStart))
            return (label, raw.split(whereSeparator: \.isWhitespace).joined(separator: " "))
        }
    }

    // MARK: Field parsers

    /// "MoWe" -> [.mon, .wed]. Two-letter tokens; unknown tokens (Sa, Su, TBA) are dropped.
    static func parseDays(_ raw: String) -> [Weekday] {
        let chars = Array(raw.filter { !$0.isWhitespace })
        return stride(from: 0, to: chars.count - 1, by: 2).compactMap {
            Weekday(token: String(chars[$0...$0 + 1]))
        }
    }

    /// "1:25 PM" -> 805 (minutes after midnight). Nil for "TBA" and anything else.
    static func parseMinutes(_ raw: String) -> Int? {
        guard let g = captures(#"^(\d{1,2}):(\d{2})\s*([AaPp][Mm])$"#, in: raw.trimmingCharacters(in: .whitespaces)),
              let hour = Int(g[0]), let minute = Int(g[1]), (1...12).contains(hour), minute < 60
        else { return nil }
        let isPM = g[2].uppercased() == "PM"
        return ((hour % 12) + (isPM ? 12 : 0)) * 60 + minute
    }

    /// Room strings come truncated in two shapes:
    ///   "Sitterson Hall (inc-Rm FB009"  and  "Fetzer Hall-Rm 0109".
    /// Both become building + room. Anything else is kept whole as the building.
    static func parseRoom(_ raw: String) -> (building: String, room: String) {
        let text = raw.trimmingCharacters(in: .whitespaces)
        if let g = captures(#"^(.+?)\s*(?:\(inc-Rm|-Rm)\s*(.*)$"#, in: text) {
            return (g[0].trimmingCharacters(in: .whitespaces), g[1].trimmingCharacters(in: .whitespaces))
        }
        return (text, "")
    }

    /// "08/17 - 12/11" -> dates in `year` (the PDF omits the year). If the end month
    /// is before the start month the range crosses New Year, so the end is next year.
    static func parseDates(_ raw: String, year: Int, calendar: Calendar) -> (start: Date, end: Date) {
        func date(_ month: Int, _ day: Int, _ year: Int) -> Date {
            calendar.date(from: DateComponents(year: year, month: month, day: day)) ?? .distantPast
        }
        guard let g = captures(#"(\d{1,2})/(\d{1,2})\s*-\s*(\d{1,2})/(\d{1,2})"#, in: raw),
              let m1 = Int(g[0]), let d1 = Int(g[1]), let m2 = Int(g[2]), let d2 = Int(g[3])
        else { return (date(1, 1, year), date(12, 31, year)) }
        return (date(m1, d1, year), date(m2, d2, m2 < m1 ? year + 1 : year))
    }

    // MARK: Regex helpers

    private static func matches(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }

    /// Capture groups of the first match, or nil.
    private static func captures(_ pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else { return nil }
        let ns = text as NSString
        return (1..<match.numberOfRanges).map {
            let range = match.range(at: $0)
            return range.location == NSNotFound ? "" : ns.substring(with: range)
        }
    }
}

// MARK: - Titles

/// ConnectCarolina descriptions are uppercase and abbreviated ("SOFTWARE ENGRNG LAB").
nonisolated enum CourseTitleFormatter {
    /// Hand-tuned names for the demo schedule, checked before the generic rules.
    private static let overrides = [
        "SOFTWARE ENGRNG LAB": "Software Engineering Lab",
        "MOBILE COMPUTING SYST": "Mobile Computing Systems",
        "TEXTUAL ANALYSIS WITH R": "Textual Analysis with R",
        "INTRO TO COMP VISION": "Intro to Computer Vision",
    ]

    private static let expansions = [
        "ENGRNG": "Engineering", "SYST": "Systems", "SYS": "Systems", "COMP": "Computer",
        "SCI": "Science", "PROG": "Programming", "MGMT": "Management", "ANALYS": "Analysis",
    ]

    private static let smallWords: Set<String> = ["to", "with", "of", "and", "in", "for", "the", "an", "on", "at", "or"]

    static func format(_ raw: String) -> String {
        let cleaned = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        if let override = overrides[cleaned.uppercased()] { return override }

        let words = cleaned.split(separator: " ").map(String.init)
        return words.enumerated().map { index, word in
            let upper = word.uppercased()
            if let expanded = expansions[upper] { return expanded }
            // Single letters ("R"), numerals ("II") and words with digits ("3D") stay uppercase.
            if word.count == 1 || upper.range(of: #"^[IVX]+$"#, options: .regularExpression) != nil
                || upper.contains(where: \.isNumber) { return upper }
            if index > 0, smallWords.contains(word.lowercased()) { return word.lowercased() }
            return word.prefix(1).uppercased() + word.dropFirst().lowercased()
        }.joined(separator: " ")
    }
}
