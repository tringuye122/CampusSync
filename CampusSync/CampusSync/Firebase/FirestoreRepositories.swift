//
//  FirestoreRepositories.swift
//  CampusSync
//
//  The Firestore-backed repositories. They wrap the local ones:
//   - Reads come from the SwiftData cache, which `SyncCoordinator` keeps current from
//     Firestore listeners. So screens load instantly and keep working offline.
//   - Writes update the cache straight away (optimistic) and send the change to
//     Firestore without waiting for the server, so Firestore's offline queue holds them
//     until the connection returns. If the rules reject a write, the listener removes
//     the optimistic copy again and the failure is logged.
//

import FirebaseAuth
import FirebaseFirestore
import Foundation

private var db: Firestore { Firestore.firestore() }
private var signedInUID: String? { Auth.auth().currentUser?.uid }

private func logWrite(_ what: String) -> (Error?) -> Void {
    { error in
        if let error { debugLog("Firestore write failed (\(what)): \(error.localizedDescription)") }
    }
}

// MARK: - Schedule

/// Publishing the student's meeting times for accepted friends. Meeting times only:
/// the rules reject any other field.
enum ScheduleSharing {
    /// Firestore rules cap a schedule at what fits in this many meeting documents.
    static let maxMeetings = 40

    /// The meetings that will be published: only ones the rules accept, so one odd class (a TBA
    /// day, a long room name) cannot make the server reject the whole schedule. Mirrors the
    /// checks in firestore.rules for `schedules/{uid}/meetings`.
    static func publishable(_ classes: [ClassSchedule]) -> [ClassMeeting] {
        classes.map(\.meeting).compactMap { meeting in
            guard !meeting.weekdays.isEmpty,
                  isPublishableCourseCode(meeting.courseCode),
                  meeting.startMinutes >= 0,
                  meeting.endMinutes > meeting.startMinutes,
                  meeting.endMinutes <= 1440
            else { return nil }
            var clean = meeting
            clean.courseCode = String(meeting.courseCode.prefix(12))
            clean.building = String(meeting.building.prefix(60))
            return clean
        }
    }

    /// "COMP 301" or "BIOL 101L": the shape the rules accept, so a stray string can never ride along.
    static func isPublishableCourseCode(_ code: String) -> Bool {
        code.wholeMatch(of: /[A-Z]{3,4} [0-9]{3}[A-Z]?/) != nil
    }

    /// Replaces the published meetings with `classes` (or removes them all when sharing is off).
    /// Documents are m0, m1, ...; any left over from a longer schedule are deleted.
    static func publish(classes: [ClassSchedule]) {
        guard let uid = signedInUID else { return }
        let meetings = ScheduleSharingSetting.isEnabled ? Array(publishable(classes).prefix(maxMeetings)) : []
        let batch = db.batch()
        let collection = db.collection("schedules").document(uid).collection("meetings")
        for index in 0..<maxMeetings {
            let document = collection.document("m\(index)")
            if index < meetings.count {
                batch.setData(FirestoreCoding.data(for: meetings[index]), forDocument: document)
            } else {
                batch.deleteDocument(document)   // deleting a missing document is allowed
            }
        }
        batch.commit(completion: logWrite("schedule"))
    }
}

@MainActor
final class FirestoreScheduleRepository: ScheduleRepository {
    private let local: LocalScheduleRepository

    init(local: LocalScheduleRepository) {
        self.local = local
    }

    func classes() async throws -> [ClassSchedule] { try await local.classes() }

    func replaceClasses(with classes: [ClassSchedule]) async throws {
        try await local.replaceClasses(with: classes)
        ScheduleSharing.publish(classes: try await local.classes())
    }

    func loadDemoSchedule() async throws {
        try await local.loadDemoSchedule()
        ScheduleSharing.publish(classes: try await local.classes())
    }

    var sharesScheduleWithFriends: Bool { local.sharesScheduleWithFriends }

    func setSharesScheduleWithFriends(_ shares: Bool) async throws {
        try await local.setSharesScheduleWithFriends(shares)
        ScheduleSharing.publish(classes: try await local.classes())   // publishes, or clears when off
    }

    /// Accepted friends, with their shared meetings, as last mirrored by `SyncCoordinator`.
    func friends() async throws -> [FriendProfile] { try await local.friends() }

    func professorRating(for instructor: String) async -> ProfessorRatingLookup {
        await local.professorRating(for: instructor)
    }
}

// MARK: - Invites

@MainActor
final class FirestoreInviteRepository: InviteRepository {
    private let local: LocalInviteRepository
    private let users: UserRepository

    init(local: LocalInviteRepository, users: UserRepository) {
        self.local = local
        self.users = users
    }

    func activeInvites(now: Date) async throws -> [OpenInvite] {
        try await local.activeInvites(now: now)
    }

    func post(_ invite: OpenInvite) async throws {
        try await local.post(invite)
        db.collection("invites").document(invite.id)
            .setData(FirestoreCoding.data(for: invite), completion: logWrite("post invite"))
    }

    func toggleRSVP(inviteID: String) async throws {
        let user = try await users.currentUser()
        let wasGoing = try await local.activeInvites(now: .distantPast)
            .first { $0.id == inviteID }?.attendeeIDs.contains(user.id) ?? false
        try await local.toggleRSVP(inviteID: inviteID)   // checks capacity too
        // arrayUnion/arrayRemove touch only this student, which is all the rules allow.
        let change: FieldValue = wasGoing ? .arrayRemove([user.id]) : .arrayUnion([user.id])
        db.collection("invites").document(inviteID)
            .updateData(["attendeeIDs": change], completion: logWrite("RSVP"))
    }
}

// MARK: - Clubs

@MainActor
final class FirestoreClubRepository: ClubRepository {
    private let local: LocalClubRepository
    private let users: UserRepository

    init(local: LocalClubRepository, users: UserRepository) {
        self.local = local
        self.users = users
    }

    func clubs() async throws -> [Club] { try await local.clubs() }

    func events(now: Date) async throws -> [ClubEvent] { try await local.events(now: now) }

    func joinClub(id: String) async throws {
        let user = try await users.currentUser()
        let alreadyMember = user.joinedClubIDs.contains(id)
        try await local.joinClub(id: id)
        guard !alreadyMember else { return }
        db.collection("users").document(user.id).collection("memberships").document(id)
            .setData(["joinedAt": FieldValue.serverTimestamp(), "duesPaid": false], completion: logWrite("join club"))
    }

    /// No real payment: records a membership with `duesPaid` set, which shows the Verified Member badge.
    func payDues(clubID: String) async throws {
        let user = try await users.currentUser()
        let alreadyMember = user.joinedClubIDs.contains(clubID)
        try await local.payDues(clubID: clubID)   // throws if it is not a dues club
        let membership = db.collection("users").document(user.id).collection("memberships").document(clubID)
        if alreadyMember {
            membership.updateData(["duesPaid": true], completion: logWrite("pay dues"))
        } else {
            membership.setData(["joinedAt": FieldValue.serverTimestamp(), "duesPaid": true], completion: logWrite("pay dues"))
        }
    }

    func leaveClub(id: String) async throws {
        let user = try await users.currentUser()
        try await local.leaveClub(id: id)
        db.collection("users").document(user.id).collection("memberships").document(id)
            .delete(completion: logWrite("leave club"))
    }

    func postEvent(_ draft: ClubEventDraft) async throws -> ClubEvent {
        let event = try await local.postEvent(draft)
        db.collection("clubs").document(event.clubID).collection("events").document(event.id)
            .setData(FirestoreCoding.data(for: event), completion: logWrite("post club event"))
        return event
    }

    func deleteEvent(id: String) async throws {
        let clubID = try await local.events(now: .distantPast).first { $0.id == id }?.clubID
        try await local.deleteEvent(id: id)
        if let clubID {
            db.collection("clubs").document(clubID).collection("events").document(id)
                .delete(completion: logWrite("delete club event"))
        }
    }
}
