//
//  DemoWorld.swift
//  CampusSync
//
//  Demo mode's data: an in-memory database holding the demo user's schedule (the sample
//  ConnectCarolina PDF), a cast of fictional friends with schedules, and invites from them, plus
//  the repositories on top of it. Turning demo mode on swaps these in for the live repositories;
//  turning it off drops this object, so nothing here ever reaches Firestore or the live cache.
//  Clubs, sign-in and Join / Pay Dues stay live. The cast mirrors `firebase/seed/demo-data.mjs`.
//

import Foundation
import SwiftData

/// A fictional student in the demo cast.
struct DemoPerson {
    let id: String
    let name: String
    /// Lowercase, without the "@".
    let handle: String
    let meetings: [ClassMeeting]

    var summary: FriendSummary { FriendSummary(id: id, displayName: name, handle: handle) }
}

enum DemoCast {
    private static func meeting(_ code: String, _ days: [Weekday], _ start: (Int, Int), _ end: (Int, Int), _ building: String) -> ClassMeeting {
        ClassMeeting(courseCode: code, weekdays: days, startMinutes: start.0 * 60 + start.1,
                     endMinutes: end.0 * 60 + end.1, building: building)
    }

    static let maya = DemoPerson(id: "demo-maya", name: "Maya Patel", handle: "maya_demo", meetings: [
        meeting("COMP 410", [.tue, .thu], (9, 30), (10, 45), "Sitterson Hall"),
        meeting("MATH 233", [.mon, .wed], (11, 0), (12, 15), "Phillips Hall"),
        meeting("STOR 435", [.tue, .thu], (15, 30), (16, 45), "Hanes Hall"),
    ])
    static let alex = DemoPerson(id: "demo-alex", name: "Alex Morgan", handle: "alex_demo", meetings: [
        meeting("MATH 232", [.tue, .thu], (9, 0), (10, 15), "Phillips Hall"),
        meeting("MATH 347", [.mon, .wed, .fri], (10, 10), (11, 0), "Phillips Hall"),
        meeting("PHYS 118", [.tue, .thu], (17, 0), (18, 15), "Phillips Hall"),
    ])
    static let jordan = DemoPerson(id: "demo-jordan", name: "Jordan Lee", handle: "jordan_demo", meetings: [
        meeting("CHEM 101", [.mon, .wed], (8, 0), (9, 15), "Venable Hall"),
        meeting("BIOL 101", [.tue, .thu], (12, 0), (13, 15), "Coker Hall"),
        meeting("BIOL 205", [.mon, .wed], (14, 0), (15, 15), "Coker Hall"),
    ])
    static let dee = DemoPerson(id: "demo-dee", name: "Dee Carter", handle: "dee_demo", meetings: [
        meeting("ECON 101", [.tue, .thu], (9, 0), (10, 15), "Gardner Hall"),
        meeting("STOR 155", [.mon, .wed, .fri], (11, 15), (12, 5), "Hanes Hall"),
        meeting("ECON 310", [.tue, .thu], (15, 0), (16, 15), "Gardner Hall"),
    ])
    /// Has a pending request to the demo user, so Accept can be shown.
    static let sam = DemoPerson(id: "demo-sam", name: "Sam Rivera", handle: "sam_demo", meetings: [
        meeting("CHEM 261", [.tue, .thu], (10, 0), (11, 15), "Venable Hall"),
    ])
    /// Findable by handle, with no schedule and no request: for showing search and Add.
    static let riley = DemoPerson(id: "demo-riley", name: "Riley Chen", handle: "riley_demo", meetings: [])

    static let friends = [maya, alex, jordan, dee]
    static var directory: [DemoPerson] { friends + [sam, riley] }
}

@MainActor
final class DemoWorld {
    /// Tuesday, Oct 13, 2026, 12:30 PM: the demo user's gap between COMP 433 and COMP 577, when
    /// Maya and Alex are free with them, Dee is free and Jordan is in class.
    nonisolated static func moment(calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 12, minute: 30))!
    }

    let container: ModelContainer
    let userID: String
    let users: UserRepository
    let schedule: ScheduleRepository
    let invites: InviteRepository
    let friends: FriendRepository

    /// `account` is the signed-in student, so the demo carries their name and id. `liveUsers`
    /// supplies their real club memberships, since clubs stay live.
    init(account: UserAccount?, liveUsers: UserRepository, ratings: ProfessorRatingProvider, now: Date = DemoWorld.moment()) throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Schema(AppSchema.models), configurations: configuration)
        let context = container.mainContext
        let userID = account?.uid ?? "demo-me"

        context.insert(UserProfile(
            id: userID, displayName: account?.displayName ?? "Demo Student",
            handle: account?.handle ?? "demo", friendIDs: DemoCast.friends.map(\.id)))
        SampleData.classes().forEach(context.insert)
        for person in DemoCast.friends {
            context.insert(FriendProfile(id: person.id, displayName: person.name, classes: person.meetings))
        }
        Self.invites(now: now, userID: userID).forEach(context.insert)
        try context.save()

        self.container = container
        self.userID = userID
        let localUsers = LocalUserRepository(context: context)
        users = DemoUserRepository(demo: localUsers, live: liveUsers)
        schedule = LocalScheduleRepository(context: context, ratings: ratings)
        invites = LocalInviteRepository(context: context)

        let me = FriendSummary(id: userID, displayName: account?.displayName ?? "Demo Student", handle: account?.handle ?? "demo")
        let inMemory = InMemoryFriendRepository(
            me: me, directory: DemoCast.directory.map(\.summary), friends: DemoCast.friends.map(\.summary))
        inMemory.receiveRequest(from: DemoCast.sam.summary)
        friends = DemoFriendRepository(inner: inMemory, context: context, userID: userID)
    }

    /// Friend invites timed from the demo moment, so none are expired when the clock reads it.
    static func invites(now: Date, userID: String) -> [OpenInvite] {
        func at(_ minutes: Int) -> Date { now.addingTimeInterval(TimeInterval(minutes * 60)) }
        func invite(_ host: DemoPerson, _ title: String, _ landmark: Landmark, _ category: InviteCategory, start: Int, length: Int) -> OpenInvite {
            OpenInvite(
                id: "demo-invite-\(host.handle.replacingOccurrences(of: "_demo", with: ""))",
                title: title, landmark: landmark, category: category,
                startTime: at(start), expiresAt: at(start + length),
                hostID: host.id, hostName: host.name,
                attendeeIDs: [host.id], recipientIDs: [userID], capacity: 8)
        }
        return [
            invite(DemoCast.maya, "Quick lunch at Chase", .chaseDiningHall, .food, start: 30, length: 60),
            invite(DemoCast.dee, "Coffee at the Union", .studentUnion, .social, start: 90, length: 60),
            invite(DemoCast.alex, "Study session at Davis", .davisLibrary, .study, start: 150, length: 120),
        ]
    }
}
