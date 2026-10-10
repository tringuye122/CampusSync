//
//  RateMyProfessorClient.swift
//  CampusSync
//
//  Looks up a professor on RateMyProfessors.com. RateMyProfessors has no
//  official public API; this uses the same GraphQL endpoint its website (and
//  browser extensions) use, so it can change or stop working without notice and
//  its terms of use apply. That is why results are cached and every failure
//  degrades to "no rating" instead of breaking a screen.
//

import Foundation

nonisolated protocol ProfessorSearching: Sendable {
    /// Nil when nobody at the school matches. Throws on network or decoding problems.
    func search(name: String) async throws -> ProfessorRating?
}

nonisolated struct RateMyProfessorClient: ProfessorSearching {
    /// The University of North Carolina at Chapel Hill (RateMyProfessors school 1232).
    static let uncSchoolID = "U2Nob29sLTEyMzI="

    var session: URLSession = .shared
    var schoolID = uncSchoolID
    var endpoint = URL(string: "https://www.ratemyprofessors.com/graphql")!

    func search(name: String) async throws -> ProfessorRating? {
        let tokens = name.split(whereSeparator: \.isWhitespace)
        guard tokens.count >= 2 else { return nil }
        // First and last name only: middle names make the search miss.
        let query = "\(tokens.first!) \(tokens.last!)"

        let (data, response) = try await session.data(for: request(for: query))
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return ProfessorNameMatcher.bestMatch(for: name, in: try Self.parse(data))
    }

    func request(for text: String) throws -> URLRequest {
        var request = URLRequest(url: endpoint, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // The public site token ("test:test") that RateMyProfessors' own web client sends.
        request.setValue("Basic dGVzdDp0ZXN0", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "query": Self.queryText,
            "variables": ["q": ["text": text, "schoolID": schoolID]],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    static let queryText = """
    query($q: TeacherSearchQuery!) {
      newSearch {
        teachers(query: $q, first: 8) {
          edges { node { legacyId firstName lastName department avgRating avgDifficulty wouldTakeAgainPercent numRatings } }
        }
      }
    }
    """

    // MARK: Decoding

    private struct Envelope: Decodable {
        struct Edge: Decodable { let node: Node }
        struct Node: Decodable {
            let legacyId: Int
            let firstName: String
            let lastName: String
            let department: String?
            let avgRating: Double
            let avgDifficulty: Double
            let wouldTakeAgainPercent: Double?
            let numRatings: Int
        }
        struct Teachers: Decodable { let edges: [Edge] }
        struct NewSearch: Decodable { let teachers: Teachers }
        struct DataBody: Decodable { let newSearch: NewSearch }
        let data: DataBody
    }

    static func parse(_ data: Data) throws -> [ProfessorRating] {
        try JSONDecoder().decode(Envelope.self, from: data).data.newSearch.teachers.edges.map { edge in
            let node = edge.node
            return ProfessorRating(
                legacyID: node.legacyId,
                firstName: node.firstName.trimmingCharacters(in: .whitespaces),
                lastName: node.lastName.trimmingCharacters(in: .whitespaces),
                department: node.department,
                overallRating: node.avgRating,
                difficulty: node.avgDifficulty,
                // RateMyProfessors sends -1 when nobody answered the question.
                wouldTakeAgainPercent: (node.wouldTakeAgainPercent ?? -1) >= 0 ? node.wouldTakeAgainPercent : nil,
                numRatings: node.numRatings)
        }
    }
}
