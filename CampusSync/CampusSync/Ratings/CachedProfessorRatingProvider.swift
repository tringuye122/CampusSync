//
//  CachedProfessorRatingProvider.swift
//  CampusSync
//
//  Network lookups with an on-disk cache, so ratings fetched once keep working
//  offline (the demo runs from the cache). Order: fresh cache, then network, then
//  stale cache, then "unavailable". Nothing here ever throws to a caller.
//

import Foundation

/// JSON file of lookups keyed by normalized instructor name.
actor ProfessorRatingStore {
    struct Entry: Codable, Equatable {
        /// Nil records "RateMyProfessors had no match".
        var rating: ProfessorRating?
        var fetchedAt: Date
    }

    private let fileURL: URL
    private var entries: [String: Entry]?

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("professor-ratings.json")
    }

    func entry(for key: String) -> Entry? {
        load()[key]
    }

    func save(_ entry: Entry, for key: String) {
        var all = load()
        all[key] = entry
        entries = all
        guard let data = try? JSONEncoder().encode(all) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL, options: .atomic)
    }

    private func load() -> [String: Entry] {
        if let entries { return entries }
        let loaded = (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode([String: Entry].self, from: $0) } ?? [:]
        entries = loaded
        return loaded
    }
}

nonisolated struct CachedProfessorRatingProvider: ProfessorRatingProvider {
    /// Found ratings are refreshed weekly; "no match" is rechecked daily.
    static let foundTTL: TimeInterval = 7 * 24 * 3600
    static let notFoundTTL: TimeInterval = 24 * 3600

    let client: ProfessorSearching
    let store: ProfessorRatingStore
    /// Real wall-clock time for cache expiry (not the demo clock override).
    var now: @Sendable () -> Date = { AppClock.now(offset: 0) }

    static func live() -> CachedProfessorRatingProvider {
        CachedProfessorRatingProvider(
            client: RateMyProfessorClient(),
            store: ProfessorRatingStore(fileURL: ProfessorRatingStore.defaultFileURL))
    }

    func rating(for instructor: String) async -> ProfessorRatingLookup {
        let key = ProfessorNameMatcher.normalize(instructor)
        guard !key.isEmpty else { return .notFound }

        let cached = await store.entry(for: key)
        if let cached, isFresh(cached) { return lookup(from: cached) }

        do {
            let rating = try await client.search(name: instructor)
            let entry = ProfessorRatingStore.Entry(rating: rating, fetchedAt: now())
            await store.save(entry, for: key)
            return lookup(from: entry)
        } catch {
            // Offline or RateMyProfessors changed: fall back to whatever we last saw.
            if let cached { return lookup(from: cached) }
            return .unavailable
        }
    }

    private func isFresh(_ entry: ProfessorRatingStore.Entry) -> Bool {
        let ttl = entry.rating == nil ? Self.notFoundTTL : Self.foundTTL
        return now().timeIntervalSince(entry.fetchedAt) < ttl
    }

    private func lookup(from entry: ProfessorRatingStore.Entry) -> ProfessorRatingLookup {
        entry.rating.map(ProfessorRatingLookup.found) ?? .notFound
    }
}
