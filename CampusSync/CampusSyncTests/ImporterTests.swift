//
//  ImporterTests.swift
//  CampusSyncTests
//
//  The text fixtures below copy the SHAPE of real ConnectCarolina PDFKit output
//  (labels, wrapped instructors, both room formats, page chrome, a card split
//  across the page break) using fictional people and a fake ID.
//

import Foundation
import SwiftData
import UniformTypeIdentifiers
import Testing
@testable import CampusSync

struct ImporterTests {
    private let fakeName = "Pat Example"
    private let fakeID = "999888777"

    private var page1: String {
        """
        10/10/26, 10:28 AM Schedule
        \(fakeName) \(fakeID) Student Schedule
        Retrieved at: 2026-10-10 10:27:58-04:00
        Term: 2026 Fall
        COMP 523
        Section: 001
        Description: SOFTWARE ENGRNG LAB
        Wait List Position: -
        Units: 4
        Instructor: Ada Lovelace, Grace Hopper
        Days: MoWe
        Start: 1:25 PM
        End: 2:40 PM
        Room: Sitterson Hall (inc-Rm FB009
        Dates: 08/17 - 12/11
        COMP 433
        Section: 001
        Description: MOBILE COMPUTING SYST
        Wait List Position: -
        Units: 3
        Instructor: Alan Turing, Grace Hopper, Katherine
        Johnson, Dorothy Vaughan
        Days: TuTh
        Start: 11:00 AM
        End: 12:15 PM
        Room: Sitterson Hall (inc-Rm SN014
        Dates: 08/17 - 12/11
        LING 460
        Section: 001
        Description: TEXTUAL ANALYSIS WITH R
        Wait List Position: -
        Units: 3
        Instructor: Noam Chomsky, Barbara Partee
        Days: TuTh
        Start: 5:00 PM
        End: 6:15 PM
        Room: Fetzer Hall-Rm 0109
        Dates: 08/17 - 12/11
        https://pa.cc.unc.edu/psp/paprd/EMPLOYEE/SA/s/WEBLIB
        HCX
        GN.H
        _
        DASHBOARD.FieldFormula.IScript
        Main 1/2_
        """
    }

    private var page2: String {
        """
        10/10/26, 10:28 AM Schedule
        COMP 577
        Section: 001
        Description: INTRO TO COMP VISION
        Wait List Position: -
        Units: 3
        Instructor: Fei Fei, Yann LeCun, Geoffrey
        Hinton
        Days: TuTh
        Start: 3:30 PM
        End: 4:45 PM
        Room: Sitterson Hall (inc-Rm FB009
        Dates: 08/17 - 12/11
        https://pa.cc.unc.edu/psp/paprd/EMPLOYEE/SA/s/WEBLIB
        HCX
        Main 2/2_
        """
    }

    private var parser: ConnectCarolinaPDFParser { ConnectCarolinaPDFParser(fallbackYear: 2000) }

    // MARK: The sample shape

    @Test func parsesAllFourCoursesAcrossThePageBreak() throws {
        let result = try parser.parse(pages: [page1, page2])
        #expect(result.term == "2026 Fall")
        #expect(result.classes.map(\.courseCode) == ["COMP 523", "COMP 433", "LING 460", "COMP 577"])
        #expect(result.skipped.isEmpty)
    }

    @Test func parsesEveryFieldOfTheFirstCourse() throws {
        let cls = try #require(try parser.parse(pages: [page1, page2]).classes.first)
        #expect(cls.title == "Software Engineering Lab")
        #expect(cls.section == "001")
        #expect(cls.units == 4)
        #expect(cls.weekdays == [.mon, .wed])
        #expect(cls.startMinutes == 13 * 60 + 25)
        #expect(cls.endMinutes == 14 * 60 + 40)
        #expect(cls.building == "Sitterson Hall")
        #expect(cls.room == "FB009")
        #expect(cls.instructors == ["Ada Lovelace", "Grace Hopper"])
        #expect(cls.primaryInstructor == "Ada Lovelace")
        let calendar = Calendar.current
        #expect(calendar.dateComponents([.year, .month, .day], from: cls.startDate) == DateComponents(year: 2026, month: 8, day: 17))
        #expect(calendar.dateComponents([.year, .month, .day], from: cls.endDate) == DateComponents(year: 2026, month: 12, day: 11))
    }

    @Test func rejoinsWrappedInstructorLines() throws {
        let classes = try parser.parse(pages: [page1, page2]).classes
        #expect(classes[1].instructors == ["Alan Turing", "Grace Hopper", "Katherine Johnson", "Dorothy Vaughan"])
        #expect(classes[3].instructors == ["Fei Fei", "Yann LeCun", "Geoffrey Hinton"])
    }

    @Test func handlesBothTruncatedRoomFormats() throws {
        let classes = try parser.parse(pages: [page1, page2]).classes
        #expect(classes[1].building == "Sitterson Hall" && classes[1].room == "SN014")
        #expect(classes[2].building == "Fetzer Hall" && classes[2].room == "0109")
    }

    @Test func prettifiesTitles() throws {
        let titles = try parser.parse(pages: [page1, page2]).classes.map(\.title)
        #expect(titles == [
            "Software Engineering Lab", "Mobile Computing Systems",
            "Textual Analysis with R", "Intro to Computer Vision",
        ])
        #expect(CourseTitleFormatter.format("ADV TOPICS IN ALGORITHMS II") == "Adv Topics in Algorithms II")
    }

    @Test func producesTheSameScheduleAsTheDemoSeed() throws {
        let parsed = try parser.parse(pages: [page1, page2]).classes
        let seed = SampleData.classes()
        for demo in seed {
            let match = try #require(parsed.first { $0.courseCode == demo.courseCode })
            #expect(match.title == demo.title)
            #expect(match.weekdays == demo.weekdays)
            #expect(match.startMinutes == demo.startMinutes && match.endMinutes == demo.endMinutes)
            #expect(match.building == demo.building && match.room == demo.room)
            #expect(match.units == demo.units)
        }
    }

    // MARK: Privacy

    @Test func neverKeepsTheStudentNameOrID() throws {
        let result = try parser.parse(pages: [page1, page2])
        let dump = String(describing: result)
        #expect(!dump.contains(fakeID))
        #expect(!dump.contains(fakeName))
    }

    // MARK: Robustness

    @Test func skipsTBAAndSaturdayMeetingsAndSaysSo() throws {
        let text = """
        Term: 2026 Fall
        ART 101
        Section: 001
        Description: DRAWING
        Units: 3
        Instructor: Frida Kahlo
        Days: TBA
        Start: TBA
        End: TBA
        Room: TBA
        Dates: 08/17 - 12/11
        ART 102
        Section: 001
        Description: PAINTING
        Units: 3
        Instructor: Frida Kahlo
        Days: Sa
        Start: 9:00 AM
        End: 11:00 AM
        Room: Hanes Art Center-Rm 1
        Dates: 08/17 - 12/11
        ART 103
        Section: 001
        Description: SCULPTURE
        Units: 3
        Instructor: Frida Kahlo
        Days: Fr
        Start: 9:00 AM
        End: 11:00 AM
        Room: Hanes Art Center-Rm 2
        Dates: 08/17 - 12/11
        """
        let result = try parser.parse(pages: [text])
        #expect(result.classes.map(\.courseCode) == ["ART 103"])
        #expect(result.skipped.count == 2)
    }

    @Test func supportsMultipleMeetingRowsPerCourse() throws {
        let text = """
        Term: 2026 Spring
        BIOL 101
        Section: 001
        Description: INTRO BIOLOGY
        Units: 4
        Instructor: Rosalind Franklin
        Days: MoWe
        Start: 9:00 AM
        End: 9:50 AM
        Room: Genome Sciences-Rm 100
        Dates: 01/12 - 04/27
        Days: Fr
        Start: 2:00 PM
        End: 3:50 PM
        Room: Genome Sciences-Rm 200
        Dates: 01/12 - 04/27
        """
        let result = try parser.parse(pages: [text])
        #expect(result.term == "2026 Spring")
        #expect(result.classes.count == 2)
        #expect(result.classes[0].weekdays == [.mon, .wed])
        #expect(result.classes[1].weekdays == [.fri])
        #expect(result.classes[1].startMinutes == 14 * 60)
        #expect(result.classes[1].room == "200")
    }

    @Test func labelOrderDoesNotMatter() throws {
        let text = """
        Term: 2026 Fall
        MATH 231
        Room: Phillips Hall-Rm 332
        Units: 3
        End: 12:50 PM
        Days: MoWeFr
        Start: 12:00 PM
        Description: CALCULUS OF FUNCTIONS
        Instructor: Emmy Noether
        Dates: 08/17 - 12/11
        Section: 002
        """
        let cls = try #require(try parser.parse(pages: [text]).classes.first)
        #expect(cls.weekdays == [.mon, .wed, .fri])
        #expect(cls.startMinutes == 12 * 60 && cls.endMinutes == 12 * 60 + 50)
        #expect(cls.room == "332" && cls.section == "002")
    }

    @Test func usesFallbackYearWhenTermIsMissing() throws {
        let text = """
        MATH 231
        Section: 001
        Description: CALCULUS
        Units: 3
        Instructor: Emmy Noether
        Days: Mo
        Start: 8:00 AM
        End: 8:50 AM
        Room: Phillips Hall-Rm 1
        Dates: 08/17 - 12/11
        """
        let result = try ConnectCarolinaPDFParser(fallbackYear: 2031).parse(pages: [text])
        #expect(result.term == nil)
        #expect(Calendar.current.component(.year, from: result.classes[0].startDate) == 2031)
    }

    @Test func rejectsFilesWithNoCourses() {
        #expect(throws: ImportError.noCoursesFound) {
            try parser.parse(pages: ["Just some other document\nwith lines of text"])
        }
        #expect(throws: ImportError.unreadableFile) {
            try parser.parse(pages: ["", "  "])
        }
    }

    // MARK: Field parsers

    @Test func parsesTimesAndDays() {
        #expect(ConnectCarolinaPDFParser.parseMinutes("1:25 PM") == 805)
        #expect(ConnectCarolinaPDFParser.parseMinutes("12:00 AM") == 0)
        #expect(ConnectCarolinaPDFParser.parseMinutes("12:30 PM") == 12 * 60 + 30)
        #expect(ConnectCarolinaPDFParser.parseMinutes("TBA") == nil)
        #expect(ConnectCarolinaPDFParser.parseDays("TuTh") == [.tue, .thu])
        #expect(ConnectCarolinaPDFParser.parseDays("MoWeFr") == [.mon, .wed, .fri])
        #expect(ConnectCarolinaPDFParser.parseDays("TBA").isEmpty)
    }

    @Test func datesCrossingNewYearEndInTheNextYear() {
        let range = ConnectCarolinaPDFParser.parseDates("11/01 - 02/15", year: 2026, calendar: .current)
        #expect(Calendar.current.component(.year, from: range.end) == 2027)
    }

    // MARK: The real sample (runs only on a machine that has the git-ignored fixture)

    @Test(.enabled(if: FileManager.default.fileExists(atPath: Self.realSamplePath)))
    func parsesTheRealSamplePDF() async throws {
        let url = URL(fileURLWithPath: Self.realSamplePath)
        let result = try await ConnectCarolinaPDFParser(fallbackYear: 2000).importSchedule(from: url)
        // Counts and shapes only; never print or assert on the PDF's text.
        #expect(result.term?.hasSuffix("Fall") == true)
        #expect(result.classes.count == 4)
        #expect(result.classes.allSatisfy { !$0.instructors.isEmpty && $0.endMinutes > $0.startMinutes })
        #expect(Set(result.classes.map(\.courseCode)) == ["COMP 523", "COMP 433", "LING 460", "COMP 577"])
        // The demo seed carries this file's real instructor lists, so import and demo match exactly.
        for demo in SampleData.classes() {
            let imported = try #require(result.classes.first { $0.courseCode == demo.courseCode })
            #expect(imported.instructors == demo.instructors)
        }
    }

    private static let realSamplePath: String = {
        // .../CampusSync/CampusSyncTests/ImporterTests.swift -> repo root /LocalFixtures/Schedule.pdf
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return root.appendingPathComponent("LocalFixtures/Schedule.pdf").path
    }()
}

// MARK: - Review and save flow

@MainActor
struct ImportFlowTests {
    private struct StubImporter: ScheduleImporter {
        let result: ImportResult
        var supportedTypes: [UTType] { [.pdf] }
        func importSchedule(from url: URL) async throws -> ImportResult { result }
    }

    private func importedClass(_ code: String, instructor: String = "Ada Lovelace") -> ImportedClass {
        ImportedClass(
            courseCode: code, title: "Title", section: "001", units: 3, weekdays: [.mon],
            startMinutes: 9 * 60, endMinutes: 10 * 60, building: "Hanes Hall", room: "100",
            startDate: .distantPast, endDate: .distantFuture, instructors: [instructor])
    }

    @Test func reviewEditSaveReplacesTheSchedule() async throws {
        let container = SampleData.previewContainer(now: Date(timeIntervalSinceReferenceDate: 800_000_000))
        let services = AppServices(context: container.mainContext, retaining: container)
        let model = ImportViewModel()
        let stub = StubImporter(result: ImportResult(
            term: "2026 Fall", classes: [importedClass("ABC 100"), importedClass("DEF 200")], skipped: []))

        await model.importPDF(at: URL(fileURLWithPath: "/unused"), using: stub)
        #expect(model.isReviewing)
        #expect(model.drafts.count == 2)

        // Fix one class and drop the other.
        var fixed = model.drafts[0]
        fixed.title = "Fixed Title"
        model.update(fixed)
        model.remove(model.drafts[1])

        let saved = await model.save(services: services)
        #expect(saved)
        #expect(!model.isReviewing)

        let classes = try await services.schedule.classes()
        #expect(classes.map(\.courseCode) == ["ABC 100"])
        #expect(classes[0].title == "Fixed Title")
        // Ratings are fetched from RateMyProfessors on demand, never stored or invented.
        #expect(classes[0].professor == nil)
    }

    @Test func emptyOrFailedImportsShowAnErrorAndDoNotOpenReview() async {
        let model = ImportViewModel()
        await model.importPDF(
            at: URL(fileURLWithPath: "/unused"),
            using: StubImporter(result: ImportResult(term: nil, classes: [], skipped: ["ART 101: TBA"])))
        #expect(!model.isReviewing)
        #expect(model.errorMessage != nil)
    }
}
