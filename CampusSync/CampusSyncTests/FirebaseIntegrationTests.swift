//
//  FirebaseIntegrationTests.swift
//  CampusSyncTests
//
//  Runs the REAL FirebaseAuthBackend against the LOCAL Firebase emulators, so the
//  Swift code and firestore.rules are tested together. Skipped unless
//  FIREBASE_EMULATOR_HOST is set, and refuses to run if the app is not actually
//  pointed at the emulator, so it can never write to the real project.
//
//  Run with: firebase/run-app-tests.sh
//

import FirebaseFirestore
import Foundation
import SwiftData
import Testing
@testable import CampusSync

private let emulatorHost = ProcessInfo.processInfo.environment["FIREBASE_EMULATOR_HOST"]

@MainActor
@Suite(.enabled(if: emulatorHost != nil), .serialized)
struct FirebaseIntegrationTests {
    private let backend = FirebaseAuthBackend()

    private func requireEmulator() throws {
        // Hard stop: if this is not the emulator, never continue.
        let host = try #require(emulatorHost)
        #expect(Firestore.firestore().settings.host == "\(host):8080")
    }

    /// Opens the verification link the Auth emulator "sent" to this email.
    private func verifyEmail(_ email: String) async throws {
        let host = try #require(emulatorHost)
        let projectID = try #require(Firestore.firestore().app.options.projectID)
        let listURL = URL(string: "http://\(host):9099/emulator/v1/projects/\(projectID)/oobCodes")!
        let (data, _) = try await URLSession.shared.data(from: listURL)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let codes = try #require(json["oobCodes"] as? [[String: Any]])
        let match = try #require(codes.last { ($0["email"] as? String) == email && ($0["requestType"] as? String) == "VERIFY_EMAIL" })
        let link = try #require(match["oobLink"] as? String)
        _ = try await URLSession.shared.data(from: try #require(URL(string: link)))
    }

    private func freshEmail(_ domain: String = "unc.edu") -> String {
        "it-\(UUID().uuidString.prefix(8).lowercased())@\(domain)"
    }

    private func freshHandle() -> String {
        "h_\(UUID().uuidString.prefix(8).lowercased().replacingOccurrences(of: "-", with: ""))"
    }

    @Test func signUpVerifyAndClaimAHandleEndToEnd() async throws {
        try requireEmulator()
        let email = freshEmail()
        let handle = freshHandle()

        let created = try await backend.createUser(email: email, password: "password1", displayName: "Pat Example")
        #expect(!created.isEmailVerified)
        #expect(created.displayName == "Pat Example")

        // Rules block an unverified account from reading profiles.
        await #expect(throws: AuthError.permissionDenied) {
            _ = try await backend.fetchProfile(uid: created.uid)
        }

        try await backend.sendVerificationEmail()
        try await verifyEmail(email)
        let verified = try #require(try await backend.reloadUser())
        #expect(verified.isEmailVerified)

        #expect(try await backend.fetchProfile(uid: verified.uid) == nil)
        #expect(try await backend.isHandleAvailable(handle))
        try await backend.createProfile(uid: verified.uid, displayName: "Pat Example", handle: handle)
        #expect(try await backend.fetchProfile(uid: verified.uid) == ProfileData(displayName: "Pat Example", handle: handle))
        #expect(try await !backend.isHandleAvailable(handle))
    }

    @Test func aSecondStudentCannotTakeTheSameHandle() async throws {
        try requireEmulator()
        let handle = freshHandle()

        let first = try await backend.createUser(email: freshEmail(), password: "password1", displayName: "First")
        try await backend.sendVerificationEmail()
        try await verifyEmail(first.email)
        _ = try await backend.reloadUser()
        try await backend.createProfile(uid: first.uid, displayName: "First", handle: handle)
        try backend.signOut()

        let second = try await backend.createUser(email: freshEmail(), password: "password1", displayName: "Second")
        try await backend.sendVerificationEmail()
        try await verifyEmail(second.email)
        _ = try await backend.reloadUser()
        await #expect(throws: AuthError.handleTaken) {
            try await backend.createProfile(uid: second.uid, displayName: "Second", handle: handle)
        }
        try backend.signOut()
    }

    @Test func aVerifiedNonUNCAccountIsBlockedByTheRulesEvenIfTheAppIsBypassed() async throws {
        try requireEmulator()
        // Auth itself does not restrict domains; the rules are the real gate.
        let outsider = try await backend.createUser(email: freshEmail("gmail.com"), password: "password1", displayName: "Out Sider")
        try await backend.sendVerificationEmail()
        try await verifyEmail(outsider.email)
        _ = try await backend.reloadUser()
        await #expect(throws: AuthError.permissionDenied) {
            try await backend.createProfile(uid: outsider.uid, displayName: "Out Sider", handle: freshHandle())
        }
        try backend.signOut()
    }

    /// Creates a verified student with a profile and leaves them signed in.
    private func makeStudent(name: String) async throws -> (uid: String, email: String, handle: String) {
        let handle = freshHandle()
        let user = try await backend.createUser(email: freshEmail(), password: "password1", displayName: name)
        try await backend.sendVerificationEmail()
        try await verifyEmail(user.email)
        _ = try await backend.reloadUser()
        try await backend.createProfile(uid: user.uid, displayName: name, handle: handle)
        return (user.uid, user.email, handle)
    }

    /// The real FirestoreFriendRepository against the real rules: search, request,
    /// accept, see each other, then unfriend.
    @Test func friendRequestAcceptAndUnfriendEndToEnd() async throws {
        try requireEmulator()
        let repository = FirestoreFriendRepository()

        let ann = try await makeStudent(name: "Ann Example")
        try backend.signOut()
        let bob = try await makeStudent(name: "Bob Example")

        // Bob (signed in) finds Ann by typing the start of her handle, with "@" and case ignored.
        // Handles are "h_" plus 8 hex characters, so 6 characters is a real prefix.
        let typed = "@" + String(ann.handle.prefix(6)).uppercased()
        let matches = try await repository.searchHandles(prefix: typed)
        let found = try #require(matches.first { $0.id == ann.uid })
        #expect(found.displayName == "Ann Example")
        #expect(!matches.contains { $0.id == bob.uid })   // never lists me
        #expect(try await repository.searchHandles(prefix: "h").isEmpty)   // one letter lists nobody
        #expect(try await repository.searchHandles(prefix: "zzzz_no_such").isEmpty)

        try await repository.sendRequest(to: found)
        await #expect(throws: FriendError.requestPending) { try await repository.sendRequest(to: found) }
        #expect(try await repository.outgoingRequests().map(\.other.id) == [ann.uid])
        try backend.signOut()

        // Ann signs back in, sees the request, and accepts it.
        _ = try await backend.signIn(email: ann.email, password: "password1")
        let incoming = try #require(try await repository.incomingRequests().first)
        #expect(incoming.other.id == bob.uid)
        try await repository.accept(incoming)
        #expect(try await repository.friends().map(\.id) == [bob.uid])
        #expect(try await repository.incomingRequests().isEmpty)
        try backend.signOut()

        // Bob sees Ann too, because both friend docs were written in the accept batch.
        _ = try await backend.signIn(email: bob.email, password: "password1")
        #expect(try await repository.friends().map(\.id) == [ann.uid])
        await #expect(throws: FriendError.alreadyFriends) { try await repository.sendRequest(to: found) }

        // Unfriending clears both sides, and the accepted request with them, so adding again works.
        try await repository.unfriend(found)
        #expect(try await repository.friends().isEmpty)
        try await repository.sendRequest(to: found)   // would be denied if a stale request were left
        #expect(try await repository.outgoingRequests().count == 1)
        try backend.signOut()
        _ = try await backend.signIn(email: ann.email, password: "password1")
        #expect(try await repository.friends().isEmpty)
        try backend.signOut()
    }

    /// The sequences that used to end in "you don't have permission": adding again after a
    /// decline, and answering a request the sender already cancelled.
    @Test func reRequestingAfterDeclineAndAnsweringACancelledRequestBothWork() async throws {
        try requireEmulator()
        let repository = FirestoreFriendRepository()

        let ann = try await makeStudent(name: "Ann Example")
        try backend.signOut()
        let bob = try await makeStudent(name: "Bob Example")
        let annSummary = try #require(try await repository.searchHandles(prefix: ann.handle).first { $0.id == ann.uid })

        // Bob asks, Ann declines, Bob asks again: allowed, because the old declined request is cleared.
        try await repository.sendRequest(to: annSummary)
        try backend.signOut()
        _ = try await backend.signIn(email: ann.email, password: "password1")
        try await repository.decline(try #require(try await repository.incomingRequests().first))
        #expect(try await repository.incomingRequests().isEmpty)
        try backend.signOut()
        _ = try await backend.signIn(email: bob.email, password: "password1")
        try await repository.sendRequest(to: annSummary)

        // Ann loads the request, then Bob cancels it. Ann answering the stale copy gets a clear
        // "no longer available" error, not a permission error.
        try backend.signOut()
        _ = try await backend.signIn(email: ann.email, password: "password1")
        let stale = try #require(try await repository.incomingRequests().first)
        try backend.signOut()
        _ = try await backend.signIn(email: bob.email, password: "password1")
        try await repository.cancel(try #require(try await repository.outgoingRequests().first))
        try await repository.cancel(stale)   // cancelling twice is not an error
        try backend.signOut()
        _ = try await backend.signIn(email: ann.email, password: "password1")
        await #expect(throws: FriendError.requestGone) { try await repository.accept(stale) }
        await #expect(throws: FriendError.requestGone) { try await repository.decline(stale) }
        try backend.signOut()
    }

    // MARK: Sync (schedules, invites, clubs) end to end

    /// Polls until `condition` holds, so tests wait for listeners and queued writes.
    private func eventually(seconds: Double = 20, _ condition: () async throws -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if (try? await condition()) == true { return true }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return false
    }

    private func makeServices() throws -> AppServices {
        let container = try ModelContainer(
            for: Schema(AppSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return AppServices(
            context: container.mainContext, ratings: PreviewRatingProvider(),
            friends: FirestoreFriendRepository(), useFirestore: true, retaining: container)
    }

    /// Creates a club the way the seeding script does (admin write, bypassing rules), through
    /// the emulator's REST API with its "owner" bearer token. Clients cannot write clubs.
    private func seedDuesClub(id: String) async throws {
        let host = try #require(emulatorHost)
        let projectID = try #require(Firestore.firestore().app.options.projectID)
        var request = URLRequest(url: try #require(URL(string:
            "http://\(host):8080/v1/projects/\(projectID)/databases/(default)/documents/clubs/\(id)")))
        request.httpMethod = "PATCH"
        request.setValue("Bearer owner", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("""
        {"fields":{"name":{"stringValue":"Test Dues Club"},"summary":{"stringValue":"Test"},
        "symbol":{"stringValue":"star.fill"},"access":{"stringValue":"duesRequired"},"duesAmount":{"integerValue":"25"}}}
        """.utf8)
        let (_, response) = try await URLSession.shared.data(for: request)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
    }

    @Test func syncMirrorsSchedulesInvitesAndClubsBetweenTwoStudents() async throws {
        try requireEmulator()
        let repository = FirestoreFriendRepository()
        let db = Firestore.firestore()

        // Two students who are friends. Ann: signed up first, accepts. Bob: sends the request.
        let ann = try await makeStudent(name: "Ann Example")
        try backend.signOut()
        let bob = try await makeStudent(name: "Bob Example")
        try await repository.sendRequest(to: try #require(try await repository.searchHandles(prefix: ann.handle).first { $0.id == ann.uid }))
        try backend.signOut()
        _ = try await backend.signIn(email: ann.email, password: "password1")
        try await repository.accept(try #require(try await repository.incomingRequests().first))

        // Ann publishes her schedule and posts an invite to Bob, then waits for the server to have both.
        let annServices = try makeServices()
        let annAccount = UserAccount(uid: ann.uid, email: ann.email, displayName: "Ann Example", handle: ann.handle)
        annServices.sync.start(account: annAccount)
        try await annServices.schedule.replaceClasses(with: SampleData.classes())
        let invite = OpenInvite(
            title: "Lunch at the Pit", landmark: .thePit, category: .food,
            startTime: Date().addingTimeInterval(3600), expiresAt: Date().addingTimeInterval(7200),
            hostID: ann.uid, hostName: "Ann Example", attendeeIDs: [ann.uid], recipientIDs: [bob.uid])
        try await annServices.invites.post(invite)

        let publishedMeetings = SampleData.classes().count
        #expect(await eventually {
            let meetings = try await db.collection("schedules").document(ann.uid).collection("meetings")
                .getDocuments(source: .server)
            let invites = try await db.collection("invites").document(invite.id).getDocument(source: .server)
            return meetings.count == publishedMeetings && invites.exists
        })
        annServices.sync.stop(wipeCache: true)
        try backend.signOut()

        // Bob's cache fills from listeners alone: the invite, and Ann's meeting times (no titles).
        _ = try await backend.signIn(email: bob.email, password: "password1")
        try await seedDuesClub(id: "it-club-\(UUID().uuidString.prefix(6))")
        let bobServices = try makeServices()
        bobServices.sync.start(account: UserAccount(uid: bob.uid, email: bob.email, displayName: "Bob Example", handle: bob.handle))

        #expect(await eventually { try await bobServices.invites.activeInvites(now: Date()).map(\.id) == [invite.id] })
        #expect(await eventually {
            let friend = try await bobServices.schedule.friends().first
            return friend?.id == ann.uid && friend?.displayName == "Ann Example" && friend?.classes.count == publishedMeetings
        })
        let sharedCodes = Set(try await bobServices.schedule.friends().flatMap(\.classes).map(\.courseCode))
        #expect(sharedCodes == Set(SampleData.classes().map(\.courseCode)))

        // Bob RSVPs; the server ends up with both attendees.
        try await bobServices.invites.toggleRSVP(inviteID: invite.id)
        #expect(await eventually {
            let doc = try await db.collection("invites").document(invite.id).getDocument(source: .server)
            return Set(doc.data()?["attendeeIDs"] as? [String] ?? []) == [ann.uid, bob.uid]
        })

        // Clubs arrive by listener; joining and "paying" dues is recorded and shows Verified Member.
        #expect(await eventually { try await bobServices.clubs.clubs().contains { $0.name == "Test Dues Club" } })
        let club = try #require(try await bobServices.clubs.clubs().first { $0.name == "Test Dues Club" })
        try await bobServices.clubs.payDues(clubID: club.id)
        #expect(await eventually {
            let doc = try await db.collection("users").document(bob.uid).collection("memberships").document(club.id)
                .getDocument(source: .server)
            return doc.data()?["duesPaid"] as? Bool == true
        })
        #expect(await eventually { try await bobServices.users.currentUser().isVerifiedMember })

        bobServices.sync.stop(wipeCache: true)
        // Sign-out wipes the cache: friends' schedules must not outlive the session.
        let context = bobServices.store.context
        #expect(try context.fetchCount(FetchDescriptor<OpenInvite>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<FriendProfile>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<UserProfile>()) == 0)
        try backend.signOut()
    }

    /// Reset (Account) against the real repositories and rules: it must finish promptly and leave
    /// the server without the student's invites, club events and memberships.
    @Test func resetMyActivityFinishesAndClearsTheServer() async throws {
        try requireEmulator()
        let db = Firestore.firestore()
        let student = try await makeStudent(name: "Rae Example")
        let services = try makeServices()
        services.sync.start(account: UserAccount(uid: student.uid, email: student.email, displayName: "Rae Example", handle: student.handle))
        let clubID = "it-reset-\(UUID().uuidString.prefix(6))"
        try await seedDuesClub(id: clubID)
        #expect(await eventually { try await services.clubs.clubs().contains { $0.id == clubID } })

        try await services.clubs.payDues(clubID: clubID)
        let event = try await services.clubs.postEvent(ClubEventDraft(
            clubID: clubID, title: "Reset test", location: "Here", start: Date().addingTimeInterval(3600)))
        let invite = OpenInvite(
            title: "Reset invite", landmark: .thePit, category: .food,
            startTime: Date().addingTimeInterval(3600), expiresAt: Date().addingTimeInterval(7200),
            hostID: student.uid, hostName: "Rae Example", attendeeIDs: [student.uid], recipientIDs: ["someone-else"])
        try await services.invites.post(invite)
        #expect(await eventually {
            let membership = try await db.collection("users").document(student.uid).collection("memberships").document(clubID)
                .getDocument(source: .server)
            let eventDoc = try await db.collection("clubs").document(clubID).collection("events").document(event.id)
                .getDocument(source: .server)
            let inviteDoc = try await db.collection("invites").document(invite.id).getDocument(source: .server)
            return membership.exists && eventDoc.exists && inviteDoc.exists
        })

        let started = Date()
        try await services.resetMyActivity()
        #expect(Date().timeIntervalSince(started) < 5)   // returns, instead of spinning

        try? await Task.sleep(for: .seconds(6))
        let membershipLeft = try await db.collection("users").document(student.uid).collection("memberships").document(clubID)
            .getDocument(source: .server).exists
        let eventLeft = try await db.collection("clubs").document(clubID).collection("events").document(event.id)
            .getDocument(source: .server).exists
        // Reading a document that does not exist is denied by the invite read rule, which means it is gone.
        let inviteLeft = (try? await db.collection("invites").document(invite.id).getDocument(source: .server).exists) ?? false
        #expect(!membershipLeft, "membership still on the server")
        #expect(!eventLeft, "club event still on the server")
        #expect(!inviteLeft, "invite still on the server")
        let user = try await services.users.currentUser()
        #expect(user.joinedClubIDs.isEmpty && !user.isVerifiedMember)
        services.sync.stop(wipeCache: true)
        try backend.signOut()
    }

    @Test func wrongPasswordMapsToTheAppsOwnError() async throws {
        try requireEmulator()
        let email = freshEmail()
        _ = try await backend.createUser(email: email, password: "password1", displayName: "Pat")
        try backend.signOut()
        await #expect(throws: AuthError.wrongCredentials) {
            _ = try await backend.signIn(email: email, password: "not-the-password")
        }
        await #expect(throws: AuthError.emailInUse) {
            _ = try await backend.createUser(email: email, password: "password1", displayName: "Pat")
        }
    }
}
