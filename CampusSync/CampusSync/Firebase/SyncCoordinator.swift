//
//  SyncCoordinator.swift
//  CampusSync
//
//  Owns the Firestore listeners for the signed-in student and mirrors what they deliver
//  into the SwiftData cache. Every change bumps `changeCount` (screens reload on it) and
//  calls `onChange`, which rewrites the widget snapshot and reloads widget timelines.
//
//  Listeners are scoped to this student's own data: invites they host or were invited
//  to, their friends, their memberships, and the (small) clubs collection. Friends'
//  shared meetings are fetched when the friend list changes and on `refreshFriendSchedules()`
//  (app foreground, pull to refresh); they are not listened to individually.
//
//  Failure is soft: a listener error is logged and the cache keeps its last data.
//

import FirebaseFirestore
import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class SyncCoordinator {
    /// Bumped after every mirrored change. Views observe it to reload from the cache.
    private(set) var changeCount = 0
    private(set) var isRunning = false
    /// The most recent listener error, for diagnostics (a dev menu can show it).
    private(set) var lastError: String?

    /// Rewrites the widget snapshot and reloads timelines. Set by `AppServices`.
    @ObservationIgnored var onChange: (() async -> Void)?

    @ObservationIgnored private let context: ModelContext
    @ObservationIgnored private let store: LocalDataStore
    @ObservationIgnored private var db: Firestore { Firestore.firestore() }
    @ObservationIgnored private var listeners: [ListenerRegistration] = []
    @ObservationIgnored private var uid: String?

    // Latest raw documents from each invite query. They are merged, because a student
    // can both host invites and be invited to others.
    @ObservationIgnored private var hostedInvites: [String: [String: Any]] = [:]
    @ObservationIgnored private var receivedInvites: [String: [String: Any]] = [:]
    @ObservationIgnored private var friendIDs: [String] = []
    /// Guards against an older friend fetch overwriting a newer one.
    @ObservationIgnored private var friendFetchGeneration = 0
    @ObservationIgnored private var changePending = false
    /// Latest club names by id, so events can be refreshed without waiting for a club change.
    @ObservationIgnored private var clubNames: [String: String] = [:]

    init(context: ModelContext) {
        self.context = context
        self.store = LocalDataStore(context: context)
    }

    // MARK: Start and stop

    /// Adopts the account (resetting the cache if it belonged to someone else) and starts listening.
    func start(account: UserAccount) {
        guard uid != account.uid else { return }
        stopListening()
        var cacheWasReset = false
        do {
            cacheWasReset = try store.adoptAccount(account)
        } catch {
            lastError = "Could not prepare the local cache: \(error.localizedDescription)"
        }
        // Kept classes from before a sign-out: make sure the server copy matches (once per sign-in,
        // not at every launch, since it is a batch of writes).
        if cacheWasReset, let classes = try? context.fetch(FetchDescriptor<ClassSchedule>()), !classes.isEmpty {
            ScheduleSharing.publish(classes: classes)
        }
        uid = account.uid
        isRunning = true
        listen(uid: account.uid)
        didChange()
    }

    /// Stops listening. On sign-out the cache is wiped as well, since it holds friends' schedules.
    func stop(wipeCache: Bool) {
        stopListening()
        uid = nil
        isRunning = false
        hostedInvites = [:]
        receivedInvites = [:]
        friendIDs = []
        if wipeCache {
            // Server-sourced data goes (it includes friends' schedules); the student's own
            // imported classes stay for their next sign-in.
            try? store.wipe(keepingSchedule: true)
        }
        didChange()
    }

    private func stopListening() {
        listeners.forEach { $0.remove() }
        listeners = []
    }

    /// Listeners fire in bursts (cache then server, five of them at launch), so changes are
    /// coalesced: one `changeCount` bump and one widget reload per burst. Widget reloads are
    /// budgeted by the system, so a dozen in a row would waste it.
    private func didChange() {
        guard !changePending else { return }
        changePending = true
        Task {
            try? await Task.sleep(for: .milliseconds(300))
            changePending = false
            changeCount += 1
            await onChange?()
        }
    }

    // MARK: Listeners

    private func listen(uid: String) {
        let invites = db.collection("invites")
        add(invites.whereField("hostID", isEqualTo: uid), name: "hosted invites") { [weak self] docs in
            self?.hostedInvites = docs
            self?.reconcileInvites()
        }
        add(invites.whereField("recipientIDs", arrayContains: uid), name: "received invites") { [weak self] docs in
            self?.receivedInvites = docs
            self?.reconcileInvites()
        }
        add(db.collection("users").document(uid).collection("friends"), name: "friends") { [weak self] docs in
            self?.friendIDs = docs.keys.sorted()
            self?.applyFriendIDs()
        }
        add(db.collection("users").document(uid).collection("memberships"), name: "memberships") { [weak self] docs in
            self?.applyMemberships(docs)
        }
        add(db.collection("clubs"), name: "clubs") { [weak self] docs in
            self?.applyClubs(docs)
        }
    }

    /// Registers a listener that hands back `[documentID: data]` on every snapshot.
    private func add(_ query: Query, name: String, handler: @escaping ([String: [String: Any]]) -> Void) {
        let registration = query.addSnapshotListener { [weak self] snapshot, error in
            guard let self else { return }
            if let error {
                self.lastError = "\(name): \(error.localizedDescription)"
                print("Firestore listener failed (\(name)): \(error.localizedDescription)")
                return
            }
            guard let snapshot else { return }
            var docs: [String: [String: Any]] = [:]
            for document in snapshot.documents { docs[document.documentID] = document.data() }
            handler(docs)
        }
        listeners.append(registration)
    }

    // MARK: Mirroring into the cache

    private var localUser: UserProfile? {
        try? context.fetch(FetchDescriptor<UserProfile>()).first
    }

    private func reconcileInvites() {
        guard let uid else { return }
        let remote = hostedInvites.merging(receivedInvites) { first, _ in first }
        var existing: [String: OpenInvite] = [:]
        for invite in (try? context.fetch(FetchDescriptor<OpenInvite>())) ?? [] { existing[invite.id] = invite }

        for (id, data) in remote {
            guard let fresh = FirestoreCoding.invite(id: id, data: data) else { continue }
            if let current = existing[id] {
                current.title = fresh.title
                current.landmark = fresh.landmark
                current.category = fresh.category
                current.startTime = fresh.startTime
                current.expiresAt = fresh.expiresAt
                current.hostID = fresh.hostID
                current.hostName = fresh.hostName
                current.attendeeIDs = fresh.attendeeIDs
                current.recipientIDs = fresh.recipientIDs
                current.capacity = fresh.capacity
            } else {
                context.insert(fresh)
            }
        }
        // Anything no longer on the server (deleted, or an optimistic write the rules rejected).
        for (id, invite) in existing where remote[id] == nil { context.delete(invite) }

        localUser?.rsvpedInviteIDs = remote.compactMap { id, data in
            (data["attendeeIDs"] as? [String])?.contains(uid) == true ? id : nil
        }
        save()
    }

    private func applyFriendIDs() {
        localUser?.friendIDs = friendIDs
        save()
        Task { await refreshFriendSchedules() }
    }

    /// Pulls friends' shared meetings and club events. Called when the app comes to the
    /// foreground, since neither is listened to live.
    func refreshAll() async {
        async let friends: Void = refreshFriendSchedules()
        async let events: Void = refreshEvents()
        _ = await (friends, events)
    }

    /// Fetches each friend's name and shared meetings into `FriendProfile`. A friend whose
    /// fetch fails keeps their previously cached profile.
    func refreshFriendSchedules() async {
        guard uid != nil else { return }
        friendFetchGeneration += 1
        let generation = friendFetchGeneration
        let ids = friendIDs

        // One task per friend, so a long friend list costs one round trip's time, not 2N.
        var fetched: [String: (name: String, meetings: [ClassMeeting])] = [:]
        await withTaskGroup(of: (String, String, [ClassMeeting])?.self) { group in
            for id in ids {
                group.addTask { @MainActor [db] in
                    do {
                        let profile = try await db.collection("users").document(id).getDocument()
                        guard let name = profile.data()?["displayName"] as? String else { return nil }
                        let docs = try await db.collection("schedules").document(id).collection("meetings").getDocuments()
                        return (id, name, docs.documents.compactMap { FirestoreCoding.meeting(data: $0.data()) })
                    } catch {
                        print("Could not load friend \(id): \(error.localizedDescription)")
                        return nil
                    }
                }
            }
            for await result in group {
                if let (id, name, meetings) = result { fetched[id] = (name, meetings) }
            }
        }
        guard generation == friendFetchGeneration, uid != nil else { return }   // a newer fetch started

        var existing: [String: FriendProfile] = [:]
        for friend in (try? context.fetch(FetchDescriptor<FriendProfile>())) ?? [] { existing[friend.id] = friend }
        for id in ids {
            guard let info = fetched[id] else { continue }
            if let current = existing[id] {
                current.displayName = info.name
                current.classes = info.meetings
            } else {
                context.insert(FriendProfile(id: id, displayName: info.name, classes: info.meetings))
            }
        }
        for (id, friend) in existing where !ids.contains(id) { context.delete(friend) }
        save()
    }

    private func applyMemberships(_ docs: [String: [String: Any]]) {
        guard let user = localUser else { return }
        user.joinedClubIDs = docs.keys.sorted()
        user.isVerifiedMember = docs.values.contains { ($0["duesPaid"] as? Bool) == true }
        save()
    }

    private func applyClubs(_ docs: [String: [String: Any]]) {
        var existing: [String: Club] = [:]
        for club in (try? context.fetch(FetchDescriptor<Club>())) ?? [] { existing[club.id] = club }
        var names: [String: String] = [:]
        for (id, data) in docs {
            guard let fresh = FirestoreCoding.club(id: id, data: data) else { continue }
            names[id] = fresh.name
            if let current = existing[id] {
                current.name = fresh.name
                current.summary = fresh.summary
                current.symbol = fresh.symbol
                current.access = fresh.access
                current.duesAmount = fresh.duesAmount
            } else {
                context.insert(fresh)
            }
        }
        for (id, club) in existing where docs[id] == nil { context.delete(club) }
        clubNames = names
        save()
        Task { await refreshEvents() }
    }

    /// Club events are public, so they come from each club's `events` subcollection. They are
    /// fetched in parallel, one task per club.
    func refreshEvents() async {
        let names = clubNames
        var remote: [String: ClubEvent] = [:]
        await withTaskGroup(of: [ClubEvent].self) { group in
            for (clubID, clubName) in names {
                group.addTask { @MainActor [db] in
                    guard let snapshot = try? await db.collection("clubs").document(clubID).collection("events").getDocuments()
                    else { return [] }
                    return snapshot.documents.compactMap {
                        FirestoreCoding.event(id: $0.documentID, clubID: clubID, clubName: clubName, data: $0.data())
                    }
                }
            }
            for await events in group {
                for event in events { remote[event.id] = event }
            }
        }
        guard uid != nil else { return }
        var existing: [String: ClubEvent] = [:]
        for event in (try? context.fetch(FetchDescriptor<ClubEvent>())) ?? [] { existing[event.id] = event }
        for (id, fresh) in remote {
            if let current = existing[id] {
                current.clubID = fresh.clubID
                current.clubName = fresh.clubName
                current.title = fresh.title
                current.details = fresh.details
                current.location = fresh.location
                current.startTime = fresh.startTime
                current.access = fresh.access
                current.duesAmount = fresh.duesAmount
            } else {
                context.insert(fresh)
            }
        }
        for (id, event) in existing where remote[id] == nil { context.delete(event) }
        save()
    }

    private func save() {
        do {
            try context.save()
        } catch {
            lastError = "Could not save the local cache: \(error.localizedDescription)"
        }
        didChange()
    }
}
