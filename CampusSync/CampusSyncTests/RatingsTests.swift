//
//  RatingsTests.swift
//  CampusSyncTests
//
//  No live network: the client is stubbed and the JSON below copies the SHAPE of
//  RateMyProfessors' response using fictional professors.
//

import Foundation
import Testing
@testable import CampusSync

struct RatingsTests {
    private let json = """
    {"data":{"newSearch":{"teachers":{"edges":[
      {"node":{"legacyId":11,"firstName":"Ada","lastName":"Lovelace","department":"Mathematics","avgRating":4.5,"avgDifficulty":3.1,"wouldTakeAgainPercent":88.5714,"numRatings":40}},
      {"node":{"legacyId":12,"firstName":" Ada","lastName":"Byron","department":"History","avgRating":3.0,"avgDifficulty":2.0,"wouldTakeAgainPercent":-1,"numRatings":5}},
      {"node":{"legacyId":13,"firstName":"Alan","lastName":"Turing","department":"Computer Science","avgRating":0,"avgDifficulty":0,"wouldTakeAgainPercent":-1,"numRatings":0}}
    ]}}}}
    """

    private func rating(_ id: Int, _ first: String, _ last: String, ratings: Int = 10) -> ProfessorRating {
        ProfessorRating(legacyID: id, firstName: first, lastName: last, department: nil,
                        overallRating: 4, difficulty: 3, wouldTakeAgainPercent: 80, numRatings: ratings)
    }

    // MARK: Parsing and matching

    @Test func parsesTheResponseShape() throws {
        let teachers = try RateMyProfessorClient.parse(Data(json.utf8))
        #expect(teachers.count == 3)
        #expect(teachers[0].overallRating == 4.5)
        #expect(teachers[0].department == "Mathematics")
        // Leading space in the first name is trimmed.
        #expect(teachers[1].firstName == "Ada")
        // RateMyProfessors sends -1 for "no data".
        #expect(teachers[1].wouldTakeAgainPercent == nil)
        #expect(!teachers[2].hasRatings)
        #expect(teachers[0].profileURL?.absoluteString == "https://www.ratemyprofessors.com/professor/11")
    }

    @Test func emptyResultsDecodeToNoTeachers() throws {
        let empty = #"{"data":{"newSearch":{"teachers":{"edges":[]}}}}"#
        #expect(try RateMyProfessorClient.parse(Data(empty.utf8)).isEmpty)
    }

    @Test func matchingPrefersTheExactFullName() throws {
        let teachers = try RateMyProfessorClient.parse(Data(json.utf8))
        #expect(ProfessorNameMatcher.bestMatch(for: "Ada Lovelace", in: teachers)?.legacyID == 11)
        #expect(ProfessorNameMatcher.bestMatch(for: "ada  LOVELACE", in: teachers)?.legacyID == 11)
        #expect(ProfessorNameMatcher.bestMatch(for: "Nobody Atall", in: teachers) == nil)
        // A shared first name alone is not enough.
        #expect(ProfessorNameMatcher.bestMatch(for: "Ada Smith", in: teachers) == nil)
    }

    @Test func middleNamesStillMatchOnFirstAndLast() {
        let teachers = [rating(1, "Jun", "Choi"), rating(2, "Jane", "Choi")]
        #expect(ProfessorNameMatcher.bestMatch(for: "Jun Myeong Choi", in: teachers)?.legacyID == 1)
    }

    @Test func accentsAndPunctuationAreIgnored() {
        let teachers = [rating(5, "José", "Núñez")]
        #expect(ProfessorNameMatcher.bestMatch(for: "Jose Nunez", in: teachers)?.legacyID == 5)
    }

    @Test func ties_goToTheMostRatedEntry() {
        let teachers = [rating(1, "Sam", "Lee", ratings: 3), rating(2, "Sam", "Lee", ratings: 30)]
        #expect(ProfessorNameMatcher.bestMatch(for: "Sam Lee", in: teachers)?.legacyID == 2)
    }

    @Test func requestTargetsUNCAndSendsTheName() throws {
        let request = try RateMyProfessorClient().request(for: "Ada Lovelace")
        #expect(request.httpMethod == "POST")
        let body = try #require(request.httpBody)
        let text = String(decoding: body, as: UTF8.self)
        #expect(text.contains("Ada Lovelace"))
        #expect(text.contains(RateMyProfessorClient.uncSchoolID))
    }

    // MARK: Cache behaviour

    private final class StubSearcher: ProfessorSearching, @unchecked Sendable {
        var result: Result<ProfessorRating?, Error>
        private(set) var calls = 0
        init(_ result: Result<ProfessorRating?, Error>) { self.result = result }
        func search(name: String) async throws -> ProfessorRating? {
            calls += 1
            return try result.get()
        }
    }

    private func tempStore() -> ProfessorRatingStore {
        ProfessorRatingStore(fileURL: FileManager.default.temporaryDirectory
            .appendingPathComponent("ratings-\(UUID().uuidString).json"))
    }

    @Test func secondLookupComesFromTheCache() async {
        let stub = StubSearcher(.success(rating(1, "Ada", "Lovelace")))
        let provider = CachedProfessorRatingProvider(client: stub, store: tempStore())
        _ = await provider.rating(for: "Ada Lovelace")
        let again = await provider.rating(for: "ada lovelace")
        #expect(again == .found(rating(1, "Ada", "Lovelace")))
        #expect(stub.calls == 1)
    }

    @Test func offlineWithNothingCachedIsUnavailable() async {
        let provider = CachedProfessorRatingProvider(
            client: StubSearcher(.failure(URLError(.notConnectedToInternet))), store: tempStore())
        #expect(await provider.rating(for: "Ada Lovelace") == .unavailable)
    }

    @Test func staleCacheIsUsedWhenOffline() async {
        let store = tempStore()
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let online = CachedProfessorRatingProvider(
            client: StubSearcher(.success(rating(1, "Ada", "Lovelace"))), store: store, now: { start })
        _ = await online.rating(for: "Ada Lovelace")

        // Two weeks later the entry is stale, but the network is down.
        let later = start.addingTimeInterval(14 * 24 * 3600)
        let offline = CachedProfessorRatingProvider(
            client: StubSearcher(.failure(URLError(.notConnectedToInternet))), store: store, now: { later })
        #expect(await offline.rating(for: "Ada Lovelace") == .found(rating(1, "Ada", "Lovelace")))
    }

    @Test func staleEntriesAreRefreshedWhenOnline() async {
        let store = tempStore()
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let first = StubSearcher(.success(rating(1, "Ada", "Lovelace", ratings: 5)))
        _ = await CachedProfessorRatingProvider(client: first, store: store, now: { start }).rating(for: "Ada Lovelace")

        let later = start.addingTimeInterval(8 * 24 * 3600)
        let second = StubSearcher(.success(rating(1, "Ada", "Lovelace", ratings: 50)))
        let result = await CachedProfessorRatingProvider(client: second, store: store, now: { later }).rating(for: "Ada Lovelace")
        #expect(second.calls == 1)
        #expect(result == .found(rating(1, "Ada", "Lovelace", ratings: 50)))
    }

    @Test func notFoundIsRememberedForADay() async {
        let stub = StubSearcher(.success(nil))
        let provider = CachedProfessorRatingProvider(client: stub, store: tempStore())
        #expect(await provider.rating(for: "Nobody Atall") == .notFound)
        #expect(await provider.rating(for: "Nobody Atall") == .notFound)
        #expect(stub.calls == 1)
    }

    @Test func singleWordNamesAreNotSearched() async {
        let stub = StubSearcher(.success(rating(1, "Ada", "Lovelace")))
        let result = try? await RateMyProfessorClient().search(name: "Staff")
        #expect(result == nil)
        #expect(stub.calls == 0)
    }
}
