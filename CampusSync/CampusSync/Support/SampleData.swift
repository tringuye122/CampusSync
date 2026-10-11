//
//  SampleData.swift
//  CampusSync
//
//  Seed data. The demo runs fully offline from this file. The demo user's class
//  schedule has the real shape of the sample ConnectCarolina PDF (spec section 7),
//  so importing that PDF and "Load demo schedule" give the same result.
//  Instructor names are the real ones from that schedule; their ratings are NOT
//  stored here but fetched from RateMyProfessors (see Ratings/). Everything else
//  (friends, invites, clubs) is fictional.
//

import Foundation
import SwiftData

enum SampleData {
    // Fixed IDs so seeding is deterministic and relationships line up.
    static let userID = "seed-user-demo"
    static let mayaID = "seed-user-maya"
    static let jordanID = "seed-user-jordan"
    static let samID = "seed-user-sam"

    static let aiClubID = "seed-club-ai"
    static let csSGClubID = "seed-club-cssg"
    static let robotsClubID = "seed-club-robots"
    static let appTeamClubID = "seed-club-appteam"
    static let arvrClubID = "seed-club-arvr"

    // MARK: Time helpers

    private static func minutes(_ hour: Int, _ minute: Int = 0) -> Int { hour * 60 + minute }

    private static func date(_ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: month, day: day)) ?? Date.distantPast
    }

    // MARK: User

    static func user() -> UserProfile {
        UserProfile(
            id: userID,
            displayName: "Tri Nguyen",
            handle: "@tri",
            friendIDs: [mayaID, jordanID, samID]
        )
    }

    // MARK: Classes (shape of the sample PDF, Fall 2026, 08/17 to 12/11)

    static func classes() -> [ClassSchedule] {
        let start = date(8, 17)
        let end = date(12, 11)
        return [
            ClassSchedule(
                courseCode: "COMP 523", title: "Software Engineering Lab", section: "001", units: 4,
                weekdays: [.mon, .wed], startMinutes: minutes(13, 25), endMinutes: minutes(14, 40),
                building: "Sitterson Hall", room: "FB009", startDate: start, endDate: end,
                instructors: ["Paul Stotts", "Louie Lu"]),
            ClassSchedule(
                courseCode: "COMP 433", title: "Mobile Computing Systems", section: "001", units: 3,
                weekdays: [.tue, .thu], startMinutes: minutes(11), endMinutes: minutes(12, 15),
                building: "Sitterson Hall", room: "SN014", startDate: start, endDate: end,
                instructors: ["Shahriar Nirjon", "Louie Lu", "Tarik Reza Toha", "Zhenyu Wang"]),
            ClassSchedule(
                courseCode: "COMP 577", title: "Intro to Computer Vision", section: "001", units: 3,
                weekdays: [.tue, .thu], startMinutes: minutes(15, 30), endMinutes: minutes(16, 45),
                building: "Sitterson Hall", room: "FB009", startDate: start, endDate: end,
                instructors: ["Roni Sengupta", "Baiqi Li", "Jun Myeong Choi"]),
            ClassSchedule(
                courseCode: "LING 460", title: "Textual Analysis with R", section: "001", units: 3,
                weekdays: [.tue, .thu], startMinutes: minutes(17), endMinutes: minutes(18, 15),
                building: "Fetzer Hall", room: "0109", startDate: start, endDate: end,
                instructors: ["Daoxin Li", "Onthada Preedasawakul"]),
        ]
    }

    // MARK: Friends (built to overlap the Tue/Thu 12:15 to 3:30 PM gap)

    static func friends() -> [FriendProfile] {
        [
            FriendProfile(id: mayaID, displayName: "Maya Patel", classes: [
                ClassMeeting(courseCode: "BIOL 101", weekdays: [.tue, .thu],
                             startMinutes: minutes(9, 30), endMinutes: minutes(10, 45), building: "Genome Sciences"),
                ClassMeeting(courseCode: "PSYC 245", weekdays: [.tue, .thu],
                             startMinutes: minutes(16), endMinutes: minutes(17, 15), building: "Davie Hall"),
                ClassMeeting(courseCode: "STOR 155", weekdays: [.mon, .wed],
                             startMinutes: minutes(10), endMinutes: minutes(11, 15), building: "Hanes Hall"),
            ]),
            FriendProfile(id: jordanID, displayName: "Jordan Lee", classes: [
                ClassMeeting(courseCode: "ECON 101", weekdays: [.tue, .thu],
                             startMinutes: minutes(9, 30), endMinutes: minutes(10, 45), building: "Gardner Hall"),
                ClassMeeting(courseCode: "HIST 128", weekdays: [.tue, .thu],
                             startMinutes: minutes(15), endMinutes: minutes(16, 15), building: "Hamilton Hall"),
                ClassMeeting(courseCode: "MATH 231", weekdays: [.mon, .wed, .fri],
                             startMinutes: minutes(12), endMinutes: minutes(12, 50), building: "Phillips Hall"),
            ]),
            FriendProfile(id: samID, displayName: "Sam Rivera", classes: [
                ClassMeeting(courseCode: "CHEM 101", weekdays: [.tue, .thu],
                             startMinutes: minutes(11), endMinutes: minutes(12, 15), building: "Venable Hall"),
                ClassMeeting(courseCode: "SPAN 203", weekdays: [.tue, .thu],
                             startMinutes: minutes(17), endMinutes: minutes(18, 15), building: "Dey Hall"),
                ClassMeeting(courseCode: "COMM 140", weekdays: [.mon, .wed],
                             startMinutes: minutes(14), endMinutes: minutes(15, 15), building: "Carroll Hall"),
            ]),
        ]
    }

    // MARK: Invites (times relative to `now`, so they are never expired at demo time)

    static func invites(now: Date) -> [OpenInvite] {
        func at(_ minutesFromNow: Int) -> Date { now.addingTimeInterval(TimeInterval(minutesFromNow * 60)) }
        let everyone = [userID, mayaID, jordanID, samID]
        return [
            OpenInvite(
                title: "Quick lunch at Chase", landmark: .chaseDiningHall, category: .food,
                startTime: at(20), expiresAt: at(80), hostID: mayaID, hostName: "Maya Patel",
                attendeeIDs: [mayaID], recipientIDs: everyone, capacity: 6),
            OpenInvite(
                title: "COMP 433 study group", landmark: .davisLibrary, category: .study,
                startTime: at(45), expiresAt: at(165), hostID: samID, hostName: "Sam Rivera",
                attendeeIDs: [samID, jordanID], recipientIDs: everyone, capacity: 5),
            OpenInvite(
                title: "Hang out at the Pit", landmark: .thePit, category: .social,
                startTime: at(70), expiresAt: at(150), hostID: jordanID, hostName: "Jordan Lee",
                attendeeIDs: [jordanID], recipientIDs: everyone, capacity: 10),
            OpenInvite(
                title: "Pickup basketball", landmark: .woollenGym, category: .fitness,
                startTime: at(100), expiresAt: at(220), hostID: samID, hostName: "Sam Rivera",
                attendeeIDs: [samID], recipientIDs: [userID, samID, mayaID], capacity: 8),
            OpenInvite(
                title: "Coffee and reading", landmark: .studentUnion, category: .study,
                startTime: at(130), expiresAt: at(250), hostID: mayaID, hostName: "Maya Patel",
                attendeeIDs: [mayaID], recipientIDs: [userID, mayaID], capacity: 4),
            OpenInvite(
                title: "Frisbee on Polk Place", landmark: .polkPlace, category: .social,
                startTime: at(180), expiresAt: at(300), hostID: jordanID, hostName: "Jordan Lee",
                attendeeIDs: [jordanID, mayaID], recipientIDs: everyone, capacity: 12),
        ]
    }

    // MARK: Clubs (names are real campus clubs; the summaries, dues and events are placeholders)

    static func clubs() -> [Club] {
        [
            Club(id: aiClubID, name: "AI@UNC",
                 summary: "Talks, workshops and projects on artificial intelligence, open to everyone.",
                 symbol: "brain.head.profile", access: .public),
            Club(id: csSGClubID, name: "CS+SG",
                 summary: "Computer science students building projects and community together.",
                 symbol: "person.3.fill", access: .membersOnly),
            Club(id: robotsClubID, name: "Rams Robotics",
                 summary: "Design, build and test robots as a team.",
                 symbol: "gearshape.2.fill", access: .duesRequired, duesAmount: 25),
            Club(id: appTeamClubID, name: "App Team",
                 summary: "Build and ship mobile apps with fellow students.",
                 symbol: "iphone", access: .duesRequired, duesAmount: 15),
            Club(id: arvrClubID, name: "AR/VR UNC",
                 summary: "Explore augmented and virtual reality with demos and builds.",
                 symbol: "cube.fill", access: .public),
        ]
    }

    static func events(now: Date) -> [ClubEvent] {
        func hours(_ h: Int) -> Date { now.addingTimeInterval(TimeInterval(h * 3600)) }
        // `hours(n) + 1800` below means n hours and 30 minutes.
        return [
            ClubEvent(clubID: aiClubID, clubName: "AI@UNC",
                      title: "General meeting", details: "An intro to what we are working on this semester. Pizza provided.",
                      location: "Sitterson Hall", startTime: hours(5), endTime: hours(7), access: .public),
            ClubEvent(clubID: robotsClubID, clubName: "Rams Robotics",
                      title: "Build night", details: "Kickoff for the next robot. Bring a laptop.",
                      location: "Sitterson Hall", startTime: hours(8), endTime: hours(9) + 1800, access: .duesRequired, duesAmount: 25),
            ClubEvent(clubID: csSGClubID, clubName: "CS+SG",
                      title: "Study group", details: "Members-only study session and project help.",
                      location: "Phillips Hall", startTime: hours(22), endTime: hours(23), access: .membersOnly),
            ClubEvent(clubID: arvrClubID, clubName: "AR/VR UNC",
                      title: "Headset demo night", details: "Try the latest builds. All experience levels.",
                      location: "Davis Library", startTime: hours(27), endTime: hours(28) + 1800, access: .public),
            ClubEvent(clubID: appTeamClubID, clubName: "App Team",
                      title: "Sprint planning", details: "Plan the next release together.",
                      location: "Fred Brooks Building", startTime: hours(50), endTime: hours(52), access: .duesRequired, duesAmount: 15),
        ]
    }

    // MARK: Previews

    /// In-memory container loaded with seed data, for SwiftUI previews and tests.
    @MainActor
    static func previewContainer(now: Date = Date()) -> ModelContainer {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        // swiftlint:disable:next force_try
        let container = try! ModelContainer(for: Schema(AppSchema.models), configurations: config)
        try? LocalDataStore(context: container.mainContext).seedIfNeeded(now: now)
        return container
    }
}
