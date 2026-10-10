//
//  FirestoreFriendRepository.swift
//  CampusSync
//
//  The real FriendRepository. Every read is scoped to the signed-in student (their
//  own requests and friends subcollection); it never lists whole collections.
//  Security rules (firebase/firestore.rules) enforce the same limits, because the
//  client is never trusted on its own.
//

import FirebaseAuth
import FirebaseFirestore
import Foundation

final class FirestoreFriendRepository: FriendRepository {
    private var db: Firestore { Firestore.firestore() }

    private func myUID() throws -> String {
        guard let uid = Auth.auth().currentUser?.uid else { throw FriendError.notSignedIn }
        return uid
    }

    // MARK: Search

    /// Handles that start with `prefix`, as you type. One range query on the handle document
    /// ids (`handles/{handle}`), capped, then one profile read per match; nothing else is listed.
    /// Two or more characters are required so a single letter cannot enumerate every student.
    func searchHandles(prefix: String) async throws -> [FriendSummary] {
        let me = try myUID()
        let normalized = AuthValidator.normalizeHandle(prefix)
        guard normalized.count >= FriendSearch.minimumLength else { return [] }
        guard FriendSearch.isValidPrefix(normalized) else { throw FriendError.invalidHandle }
        do {
            let snapshot = try await db.collection("handles")
                .whereField(FieldPath.documentID(), isGreaterThanOrEqualTo: normalized)
                .whereField(FieldPath.documentID(), isLessThan: normalized + "\u{f8ff}")
                .limit(to: FriendSearch.maxResults + 1)   // +1 in case one of them is me
                .getDocuments()
            var results: [FriendSummary] = []
            for document in snapshot.documents {
                guard let uid = document.data()["uid"] as? String, uid != me else { continue }
                if let student = try? await summary(uid: uid, fallbackHandle: document.documentID) {
                    results.append(student)
                }
            }
            return Array(results.prefix(FriendSearch.maxResults))
        } catch {
            throw Self.map(error)
        }
    }

    // MARK: Requests

    func sendRequest(to student: FriendSummary) async throws {
        let me = try myUID()
        guard student.id != me else { throw FriendError.cannotAddSelf }
        do {
            // Friend docs and request queries are readable by me, so check before writing.
            let existing = try await db.collection("users").document(me)
                .collection("friends").document(student.id).getDocument()
            if existing.exists { throw FriendError.alreadyFriends }
            // Look at every request I sent to this person, whatever its status. A declined or
            // stale accepted one is still in Firestore, and sending again would be an update to
            // it, which the rules deny. So clear it first. (A pending one is a real duplicate.)
            let sent = try await rawRequests(field: "fromUID", equals: me).filter { $0.toUID == student.id }
            if sent.contains(where: { $0.status == .pending }) { throw FriendError.requestPending }
            let incoming = try await incomingRequests()
            if incoming.contains(where: { $0.fromUID == student.id }) { throw FriendError.requestPending }
            for stale in sent {
                try await db.collection("friendRequests").document(stale.id).delete()
            }
            let id = FriendRequest.makeID(from: me, to: student.id)
            try await db.collection("friendRequests").document(id).setData([
                "fromUID": me,
                "toUID": student.id,
                "status": FriendRequestStatus.pending.rawValue,
                "createdAt": FieldValue.serverTimestamp(),
            ])
        } catch {
            throw Self.map(error)
        }
    }

    func incomingRequests() async throws -> [FriendRequest] {
        let me = try myUID()
        return try await requests(field: "toUID", equals: me, otherField: "fromUID")
    }

    func outgoingRequests() async throws -> [FriendRequest] {
        let me = try myUID()
        return try await requests(field: "fromUID", equals: me, otherField: "toUID")
    }

    /// A query constrained to my own uid, which is what the read rule requires. Only
    /// pending requests are returned; answered ones are not shown.
    private func requests(field: String, equals uid: String, otherField: String) async throws -> [FriendRequest] {
        do {
            let snapshot = try await db.collection("friendRequests")
                .whereField(field, isEqualTo: uid)
                .whereField("status", isEqualTo: FriendRequestStatus.pending.rawValue)
                .getDocuments()
            var result: [FriendRequest] = []
            for document in snapshot.documents {
                let data = document.data()
                guard let from = data["fromUID"] as? String, let to = data["toUID"] as? String else { continue }
                let otherUID = (otherField == "fromUID") ? from : to
                // A request whose sender or recipient profile cannot be read is skipped, so one bad
                // profile does not hide the others (friends() does the same).
                guard let other = try? await summary(uid: otherUID, fallbackHandle: nil) else { continue }
                result.append(FriendRequest(
                    fromUID: from, toUID: to, status: .pending,
                    createdAt: (data["createdAt"] as? Timestamp)?.dateValue(), other: other))
            }
            return result.sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        } catch {
            throw Self.map(error)
        }
    }

    private struct RawRequest {
        var id: String
        var fromUID: String
        var toUID: String
        var status: FriendRequestStatus
    }

    /// My requests in any status, without loading profiles. The query is constrained to my
    /// own uid, which is what the read rule requires; a get of a missing request is denied,
    /// so existence is always checked with a query like this one.
    private func rawRequests(field: String, equals uid: String) async throws -> [RawRequest] {
        let snapshot = try await db.collection("friendRequests").whereField(field, isEqualTo: uid).getDocuments()
        return snapshot.documents.compactMap { document in
            let data = document.data()
            guard let from = data["fromUID"] as? String, let to = data["toUID"] as? String,
                  let status = (data["status"] as? String).flatMap(FriendRequestStatus.init(rawValue:))
            else { return nil }
            return RawRequest(id: document.documentID, fromUID: from, toUID: to, status: status)
        }
    }

    /// A write on a request that vanished (the sender cancelled while this screen was stale)
    /// is denied by the rules, because a missing document has no owner to check. Report that
    /// as what it is rather than as a permission problem.
    private func explainDenial(_ error: Error, requestID: String, field: String) async -> Error {
        let mapped = Self.map(error)
        guard mapped == .permissionDenied, let me = try? myUID() else { return mapped }
        let stillThere = (try? await rawRequests(field: field, equals: me))?.contains { $0.id == requestID }
        return stillThere == false ? FriendError.requestGone : mapped
    }

    /// Answering and writing both friend docs happen in one batch; the rules check the
    /// friend docs against the request as it will be after the batch (`getAfter`).
    func accept(_ request: FriendRequest) async throws {
        let me = try myUID()
        guard request.toUID == me else { throw FriendError.permissionDenied }
        do {
            let batch = db.batch()
            batch.updateData(["status": FriendRequestStatus.accepted.rawValue],
                             forDocument: db.collection("friendRequests").document(request.id))
            for (owner, friend) in [(request.fromUID, request.toUID), (request.toUID, request.fromUID)] {
                batch.setData(["since": FieldValue.serverTimestamp()],
                              forDocument: db.collection("users").document(owner)
                                .collection("friends").document(friend))
            }
            try await batch.commit()
        } catch {
            throw await explainDenial(error, requestID: request.id, field: "toUID")
        }
    }

    func decline(_ request: FriendRequest) async throws {
        let me = try myUID()
        guard request.toUID == me else { throw FriendError.permissionDenied }
        do {
            try await db.collection("friendRequests").document(request.id)
                .updateData(["status": FriendRequestStatus.declined.rawValue])
        } catch {
            throw await explainDenial(error, requestID: request.id, field: "toUID")
        }
    }

    func cancel(_ request: FriendRequest) async throws {
        let me = try myUID()
        guard request.fromUID == me else { throw FriendError.permissionDenied }
        do {
            try await db.collection("friendRequests").document(request.id).delete()
        } catch {
            // Already gone is what the student wanted, so it is not an error.
            let reason = await explainDenial(error, requestID: request.id, field: "fromUID")
            if (reason as? FriendError) == .requestGone { return }
            throw reason
        }
    }

    // MARK: Friends

    func friends() async throws -> [FriendSummary] {
        let me = try myUID()
        do {
            let snapshot = try await db.collection("users").document(me).collection("friends").getDocuments()
            var result: [FriendSummary] = []
            for document in snapshot.documents {
                if let friend = try? await summary(uid: document.documentID, fallbackHandle: nil) {
                    result.append(friend)
                }
            }
            return result.sorted { $0.displayName < $1.displayName }
        } catch {
            throw Self.map(error)
        }
    }

    /// Removes both friend docs and the answered request, so no one-sided friendship
    /// or stale accepted request is left behind.
    func unfriend(_ friend: FriendSummary) async throws {
        let me = try myUID()
        do {
            let batch = db.batch()
            batch.deleteDocument(db.collection("users").document(me).collection("friends").document(friend.id))
            batch.deleteDocument(db.collection("users").document(friend.id).collection("friends").document(me))
            try await batch.commit()
            // Clear the request that made us friends, in whichever direction it exists, so
            // no stale accepted request is left (it would block sending a new one). Only
            // requests that exist are deleted: deleting a missing document is denied.
            // Best-effort: the friendship itself is already gone.
            let between = try await rawRequests(field: "fromUID", equals: me).filter { $0.toUID == friend.id }
                + rawRequests(field: "toUID", equals: me).filter { $0.fromUID == friend.id }
            for request in between {
                try? await db.collection("friendRequests").document(request.id).delete()
            }
        } catch {
            throw Self.map(error)
        }
    }

    // MARK: Helpers

    private func summary(uid: String, fallbackHandle: String?) async throws -> FriendSummary {
        let document = try await db.collection("users").document(uid).getDocument()
        guard let data = document.data(),
              let name = data["displayName"] as? String,
              let handle = (data["handle"] as? String) ?? fallbackHandle
        else { throw FriendError.handleNotFound }
        return FriendSummary(id: uid, displayName: name, handle: handle)
    }

    static func map(_ error: Error) -> FriendError {
        if let friendError = error as? FriendError { return friendError }
        let nsError = error as NSError
        if nsError.domain == FirestoreErrorDomain {
            switch FirestoreErrorCode.Code(rawValue: nsError.code) {
            case .unavailable, .deadlineExceeded: return .offline
            case .permissionDenied, .unauthenticated: return .permissionDenied
            default: return .unknown
            }
        }
        return .unknown
    }
}
