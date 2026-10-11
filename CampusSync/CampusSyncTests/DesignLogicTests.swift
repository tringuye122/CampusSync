//
//  DesignLogicTests.swift
//  CampusSyncTests
//
//  The logic behind the redesigned screens: header text, the Home strips and "friends free now",
//  club schedule conflicts, rating tones, the new view models, and profile details.
//

import Foundation
import SwiftData
import Testing
@testable import CampusSync

private func meeting(_ day: Weekday, _ start: Int, _ end: Int, _ building: String = "A", code: String = "X 1") -> ClassMeeting {
    ClassMeeting(courseCode: code, weekdays: [day], startMinutes: start, endMinutes: end, building: building)
}

private func hm(_ hour: Int, _ minute: Int = 0) -> Int { hour * 60 + minute }

private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

private func date(_ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, year: Int = 2026) -> Date {
    utc.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

// MARK: - Header text

struct HeaderTextTests {
    @Test func initialsUseFirstAndLastWords() {
        #expect(Initials.from("Justin Nguyen") == "JN")
        #expect(Initials.from("  maya   k  patel ") == "MP")
        #expect(Initials.from("Sam") == "SA")
        #expect(Initials.from("") == "?")
    }

    @MainActor
    @Test func freeSummaryFindsTheRecurringGapBetweenClasses() {
        // The demo schedule: Tue/Thu have 12:15 to 3:30 between COMP 433 and COMP 577. Mon/Wed's
        // longer free morning is before the first class, so it does not count.
        let meetings = SampleData.classes().map(\.meeting)
        #expect(FreeWindowSummary.text(meetings: meetings) == "Free Tue/Thu 12:15–3:30")
    }

    @Test func freeSummaryIsNilWithoutAGapBetweenClasses() {
        #expect(FreeWindowSummary.text(meetings: []) == nil)
        #expect(FreeWindowSummary.text(meetings: [meeting(.mon, hm(9), hm(10))]) == nil)
        // Back-to-back classes leave no gap.
        #expect(FreeWindowSummary.text(meetings: [meeting(.mon, hm(9), hm(10)), meeting(.mon, hm(10), hm(11))]) == nil)
    }

    @Test func freeSummaryPrefersTheLongerGapThenMoreDays() {
        let meetings = [
            meeting(.mon, hm(9), hm(10)), meeting(.mon, hm(11), hm(12)),        // 1 h gap on Mon
            meeting(.wed, hm(9), hm(10)), meeting(.wed, hm(13), hm(14)),        // 3 h gap on Wed only
        ]
        #expect(FreeWindowSummary.text(meetings: meetings) == "Free Wed 10:00 AM–1:00 PM")
    }

    @Test func timeRangesDropRedundantAMPM() {
        #expect(FreeWindowSummary.range(hm(12, 15), hm(15, 30)) == "12:15–3:30")
        #expect(FreeWindowSummary.range(hm(11), hm(13, 15)) == "11:00 AM–1:15 PM")
        #expect(FreeWindowSummary.rangeWithPeriod(hm(12, 15), hm(15, 30)) == "12:15–3:30 PM")
        #expect(FreeWindowSummary.rangeWithPeriod(hm(9, 30), hm(10, 45)) == "9:30–10:45 AM")
        #expect(FreeWindowSummary.classRange(hm(11), hm(12, 15)) == "11:00–12:15 PM")   // as the design writes it
    }

    @Test func affiliationReadsLikeTheDesign() {
        #expect(ProfileDetails.affiliation(major: "CS", classYear: 2028) == "CS '28")
        #expect(ProfileDetails.affiliation(major: "  ", classYear: 2028) == "Class of '28")
        #expect(ProfileDetails.affiliation(major: "Biology", classYear: nil) == "Biology")
        #expect(ProfileDetails.affiliation(major: nil, classYear: nil) == nil)
    }

    @Test func profileDetailInputIsValidated() {
        #expect(ProfileDetails.parsedClassYear("2028") == 2028)
        #expect(ProfileDetails.parsedClassYear(" 2027 ") == 2027)
        #expect(ProfileDetails.parsedClassYear("28") == nil)
        #expect(ProfileDetails.parsedClassYear("abc") == nil)
        #expect(ProfileDetails.normalizedMajor("   ") == nil)
        #expect(ProfileDetails.normalizedMajor(String(repeating: "x", count: 50))?.count == ProfileDetails.majorMaxLength)
    }

    @Test func durationsAreSpacedLikeTheDesign() {
        #expect(45.spacedDuration == "45 min")
        #expect(60.spacedDuration == "1 h")
        #expect(195.spacedDuration == "3 h 15 min")
    }
}

// MARK: - Account profile details

@MainActor
struct ProfileDetailsAuthTests {
    private func service() -> (AuthService, MockAuthBackend) {
        let backend = MockAuthBackend(signedInEmail: "pat@unc.edu")
        backend.seed(email: "pat@unc.edu", password: "password1", displayName: "Pat Example", handle: "pat")
        let service = AuthService(backend: backend, defaults: UserDefaults(suiteName: "details-\(UUID().uuidString)")!)
        return (service, backend)
    }

    @Test func majorAndYearAreSavedAndShownInTheHeaderLine() async {
        let (auth, _) = service()
        await auth.refresh()
        #expect(auth.account?.affiliation == nil)
        await auth.updateDetails(major: " CS ", classYear: "2028")
        #expect(auth.account?.major == "CS" && auth.account?.classYear == 2028)
        #expect(auth.account?.affiliation == "CS '28")
    }

    @Test func blankOrInvalidInputClearsTheDetails() async {
        let (auth, _) = service()
        await auth.refresh()
        await auth.updateDetails(major: "CS", classYear: "2028")
        await auth.updateDetails(major: "", classYear: "nope")
        #expect(auth.account?.major == nil && auth.account?.classYear == nil)
    }

    @Test func detailsEnteredAtSetupAreSaved() async {
        let backend = MockAuthBackend()
        let auth = AuthService(backend: backend, defaults: UserDefaults(suiteName: "setup-\(UUID().uuidString)")!)
        await auth.signUp(email: "new@unc.edu", password: "password1", displayName: "New Student")
        backend.markVerified(email: "new@unc.edu")
        await auth.confirmVerification()
        await auth.createProfile(displayName: "New Student", handle: "newbie", major: "Math", classYear: "2029")
        #expect(auth.account?.handle == "newbie")
        #expect(auth.account?.affiliation == "Math '29")
    }
}

// MARK: - Home strips and friends free now

struct FriendsFreeNowTests {
    @Test func stripClipsAndMergesClassTime() {
        let strip = DayStrip.make(
            mine: [meeting(.tue, hm(9), hm(10)), meeting(.tue, hm(10), hm(11)), meeting(.tue, hm(15, 30), hm(16, 45))],
            theirs: [meeting(.tue, hm(8), hm(9, 30))],
            on: .tue, from: hm(10, 30), to: hm(18))
        #expect(strip.mine == [StripSegment(start: hm(10, 30), end: hm(11)), StripSegment(start: hm(15, 30), end: hm(16, 45))])
        #expect(strip.theirs.isEmpty)   // their class ended before the range starts
    }

    @Test func bothRowShowsOnlyMutualFreeWindowsClippedToTheRange() {
        let strip = DayStrip.make(
            mine: [meeting(.tue, hm(11), hm(12, 15)), meeting(.tue, hm(15, 30), hm(16, 45))],
            theirs: [], on: .tue, from: hm(12, 15), to: hm(18))
        #expect(strip.both.first == StripSegment(start: hm(12, 15), end: hm(15, 30)))
    }

    @MainActor
    @Test func friendsFreeWithMeRightNowAreListedLongestFirst() throws {
        // Tuesday 12:15 PM: the demo user is between COMP 433 and COMP 577.
        let mine = SampleData.classes().map(\.meeting)
        let friends = SampleData.friends().map { FriendSchedule(id: $0.id, name: $0.displayName, meetings: $0.classes) }
        let now = date(10, 13, 12, 15)
        let result = FriendsFreeNow.compute(mine: mine, friends: friends, now: now, calendar: utc)
        let maya = try #require(result.first { $0.name == "Maya Patel" })
        #expect(maya.window.startMinutes == hm(12, 15) && maya.window.endMinutes == hm(15, 30))
        #expect(maya.strip.rangeStart == hm(12, 15))
        let remaining = result.map { $0.remainingMinutes(at: hm(12, 15)) }
        #expect(remaining == remaining.sorted(by: >))
    }

    @Test func nobodyIsFreeNowOnAWeekendOrWithoutASharedSchedule() {
        let mine = [meeting(.tue, hm(9), hm(10))]
        let friends = [FriendSchedule(id: "f", name: "Fay", meetings: [meeting(.tue, hm(9), hm(10))])]
        #expect(FriendsFreeNow.compute(mine: mine, friends: friends, now: date(10, 10, 12), calendar: utc).isEmpty)   // Saturday
        let empty = [FriendSchedule(id: "e", name: "Eli", meetings: [])]
        #expect(FriendsFreeNow.compute(mine: mine, friends: empty, now: date(10, 13, 12), calendar: utc).isEmpty)
    }

    @Test func aFriendInClassRightNowIsNotListed() {
        let friends = [FriendSchedule(id: "f", name: "Fay", meetings: [meeting(.tue, hm(12), hm(13))])]
        #expect(FriendsFreeNow.compute(mine: [meeting(.tue, hm(9), hm(10))], friends: friends, now: date(10, 13, 12, 30), calendar: utc).isEmpty)
    }
}

// MARK: - Club conflicts

struct ClubAvailabilityTests {
    // LING 460: Tue/Thu 5:00 to 6:15 PM, Aug 17 to Dec 11, 2026.
    private let ling = ClassSlot(
        courseCode: "LING 460", weekdays: [.tue, .thu], startMinutes: hm(17), endMinutes: hm(18, 15),
        firstDay: date(8, 17), lastDay: date(12, 11))

    private func check(_ start: Date, _ end: Date) -> ClubAvailability {
        ClubAvailability.check(eventStart: start, eventEnd: end, classes: [ling], calendar: utc)
    }

    @Test func anOverlappingEventConflictsAndNamesTheClass() {
        #expect(check(date(10, 15, 17, 30), date(10, 15, 19)) == .conflict(courseCode: "LING 460", startMinutes: hm(17), endMinutes: hm(18, 15)))
        #expect(check(date(10, 13, 16), date(10, 13, 17, 15)) != .free)   // starts before, runs into class
    }

    @Test func touchingEdgesAndOtherTimesAreFree() {
        #expect(check(date(10, 13, 18, 15), date(10, 13, 19, 15)) == .free)   // starts the minute class ends
        #expect(check(date(10, 13, 16), date(10, 13, 17)) == .free)           // ends the minute class starts
        #expect(check(date(10, 14, 17, 30), date(10, 14, 18)) == .free)       // Wednesday: no LING
    }

    @Test func eventsOutsideTheTermOrOnWeekendsAreFree() {
        #expect(check(date(1, 12, 17, 30), date(1, 12, 18, 30), ) == .free)       // January 2026, before the term
        #expect(check(date(12, 15, 17, 30), date(12, 15, 18, 30)) == .free)      // after the term ended
        #expect(check(date(10, 10, 17, 30), date(10, 10, 18, 30)) == .free)      // Saturday
    }

    @Test func theEarliestConflictIsReported() {
        let early = ClassSlot(
            courseCode: "EARLY 1", weekdays: [.tue], startMinutes: hm(16), endMinutes: hm(17, 30),
            firstDay: date(8, 17), lastDay: date(12, 11))
        let result = ClubAvailability.check(
            eventStart: date(10, 13, 16, 30), eventEnd: date(10, 13, 18), classes: [ling, early], calendar: utc)
        #expect(result == .conflict(courseCode: "EARLY 1", startMinutes: hm(16), endMinutes: hm(17, 30)))
    }
}

// MARK: - Ratings, filters, labels

struct RatingStyleTests {
    @Test func tonesFollowTheThresholds() {
        #expect(RatingStyle.tone(for: 4.3) == .good)
        #expect(RatingStyle.tone(for: 4.0) == .good)
        #expect(RatingStyle.tone(for: 3.9) == .fair)
        #expect(RatingStyle.tone(for: 3.0) == .fair)
        #expect(RatingStyle.tone(for: 2.9) == .poor)
    }

    @Test func lowCountMeansFewerThanFiveRatings() {
        #expect(RatingStyle.isLowCount(2))
        #expect(RatingStyle.isLowCount(4))
        #expect(!RatingStyle.isLowCount(5))
    }

    @Test func numbersAreFormattedLikeTheDesign() {
        #expect(RatingStyle.ratingText(4.3) == "4.3 / 5")
        #expect(RatingStyle.ratingText(5.0) == "5 / 5")
        #expect(RatingStyle.decimalText(3.8) == "3.8")
        #expect(RatingStyle.decimalText(4.0) == "4")
        #expect(RatingStyle.percentText(86) == "86%")
        #expect(RatingStyle.percentText(nil) == "–")
    }
}

@MainActor
struct DesignViewModelTests {
    @Test func inviteChipsFilterByCategoryAndKeepSoonestFirst() async {
        let services = AppServices.preview()
        let viewModel = InvitesViewModel()
        let now = AppClock().now
        await viewModel.load(services: services, now: now)
        let all = viewModel.filteredInvites(at: now, filter: .all)
        #expect(all.map(\.startTime) == all.map(\.startTime).sorted())
        let food = viewModel.filteredInvites(at: now, filter: .category(.food))
        #expect(food.allSatisfy { $0.category == .food })
        #expect(food.count < all.count)
        #expect(InviteFilter.allCases.map(\.title) == ["All", "Food", "Study", "Fitness", "Social"])
    }

    @Test func attendeeSummaryNamesTheHost() {
        func invite(host: String, going: Int) -> OpenInvite {
            OpenInvite(
                title: "T", landmark: .thePit, category: .food, startTime: Date(), expiresAt: Date().addingTimeInterval(60),
                hostID: "h", hostName: host, attendeeIDs: (0..<going).map { "u\($0)" })
        }
        #expect(InviteAttendees.summary(for: invite(host: "Maya Patel", going: 3), isHost: false) == "Maya + 2 going")
        #expect(InviteAttendees.summary(for: invite(host: "Maya Patel", going: 1), isHost: false) == "Maya going")
        #expect(InviteAttendees.summary(for: invite(host: "Me", going: 2), isHost: true) == "You + 1 going")
    }

    @Test func inviteCountdownUsesSpacedDurations() {
        let now = date(10, 13, 12)
        let text = InviteTiming.countdownText(
            start: now.addingTimeInterval(80 * 60), expiresAt: now.addingTimeInterval(140 * 60), now: now, calendar: utc)
        #expect(text == "Starts in 1 h 20 min")
    }

    @Test func headerModelShowsTheRecurringGapAndVerifiedState() async throws {
        let services = AppServices.preview()
        let model = ProfileHeaderViewModel()
        await model.load(services: services)
        #expect(model.freeSummary == "Free Tue/Thu 12:15–3:30")
        #expect(!model.isVerifiedMember)
        try await services.clubs.payDues(clubID: SampleData.robotsClubID)
        await model.load(services: services)
        #expect(model.isVerifiedMember)
    }

    @Test func clubsFeedFiltersByMembershipAndJoinsAndPays() async throws {
        let services = AppServices.preview()
        let viewModel = ClubsViewModel()
        let now = AppClock().now
        await viewModel.load(services: services, now: now)
        #expect(viewModel.visibleItems(filter: .all).count == 5)
        #expect(viewModel.visibleItems(filter: .all).map(\.start) == viewModel.visibleItems(filter: .all).map(\.start).sorted())
        #expect(viewModel.visibleItems(filter: .joined).isEmpty)
        #expect(viewModel.visibleItems(filter: .freeForMe).allSatisfy { $0.availability.isFree })

        let film = try #require(viewModel.visibleItems(filter: .all).first { $0.clubID == SampleData.aiClubID })
        await viewModel.act(on: film, services: services)           // free club: Join
        await viewModel.load(services: services, now: now)
        #expect(viewModel.visibleItems(filter: .joined).map(\.clubID) == [SampleData.aiClubID])

        let robots = try #require(viewModel.visibleItems(filter: .all).first { $0.clubID == SampleData.robotsClubID })
        #expect(robots.access == .duesRequired)
        await viewModel.act(on: robots, services: services)          // dues club: Pay Dues (also joins)
        await viewModel.load(services: services, now: now)
        #expect(Set(viewModel.visibleItems(filter: .joined).map(\.clubID)) == [SampleData.aiClubID, SampleData.robotsClubID])
        #expect(try await services.users.currentUser().isVerifiedMember)
    }

    @Test func routerCanJumpToAFriendsOverlap() {
        let router = AppRouter()
        router.showFriendOverlap(friendID: "maya")
        #expect(router.selectedTab == .schedule)
        #expect(router.scheduleSegment == .friends)
        #expect(router.focusedFriendID == "maya")
    }

    @Test func overlapFocusSelectsTheFriendFromAHomeCard() async throws {
        let services = AppServices.preview()
        let viewModel = FriendOverlapViewModel()
        await viewModel.load(services: services, focus: SampleData.samID)
        #expect(viewModel.selectedFriendID == SampleData.samID)
        viewModel.selectedDay = .tue
        #expect(viewModel.windows(on: .tue).allSatisfy { $0.weekday == .tue })
        #expect(viewModel.longestWindow(with: try #require(viewModel.selectedFriend), on: .tue) != nil)
    }
}

struct FriendStatusTests {
    private func status(_ friends: [FriendSchedule], mine: [ClassMeeting], now: Date) -> [String: FriendStatus.State] {
        Dictionary(uniqueKeysWithValues: FriendsFreeNow.statuses(mine: mine, friends: friends, now: now, calendar: utc)
            .map { ($0.name, $0.state) })
    }

    @Test func everyFriendGetsAStatus() {
        let mine = [meeting(.tue, hm(11), hm(12, 15)), meeting(.tue, hm(15, 30), hm(16, 45))]
        let friends = [
            FriendSchedule(id: "a", name: "Ann", meetings: [meeting(.tue, hm(9), hm(10))]),               // free with me
            FriendSchedule(id: "b", name: "Bo", meetings: [meeting(.tue, hm(12), hm(13))]),               // in class
            FriendSchedule(id: "c", name: "Cy", meetings: []),                                            // nothing shared
        ]
        let result = status(friends, mine: mine, now: date(10, 13, 12, 30))
        #expect(result["Ann"] == .mutualFree(until: hm(15, 30)))
        #expect(result["Bo"] == .inClass(until: hm(13)))
        #expect(result["Cy"] == .notShared)
    }

    @Test func aFriendFreeWhileIAmInClassIsFreeButNotMutual() {
        // I am in class 12-13; Sam is free until his 14:30 class, so "Free for 2 h".
        let mine = [meeting(.tue, hm(12), hm(13))]
        let friends = [FriendSchedule(id: "s", name: "Sam", meetings: [meeting(.tue, hm(14, 30), hm(15, 30))])]
        #expect(status(friends, mine: mine, now: date(10, 13, 12, 30))["Sam"] == .free(minutes: 120))
    }

    @Test func backToBackClassesCountAsOneStretchInClass() {
        let friends = [FriendSchedule(id: "f", name: "Fay", meetings: [meeting(.tue, hm(12), hm(13)), meeting(.tue, hm(13), hm(14))])]
        #expect(status(friends, mine: [meeting(.tue, hm(9), hm(10))], now: date(10, 13, 12, 30))["Fay"] == .inClass(until: hm(14)))
    }

    @Test func weekendFriendsWhoShareAreFreeAndOthersAreNotShared() {
        let friends = [
            FriendSchedule(id: "f", name: "Fay", meetings: [meeting(.tue, hm(12), hm(13))]),
            FriendSchedule(id: "e", name: "Eli", meetings: []),
        ]
        let result = status(friends, mine: [], now: date(10, 10, 12))   // Saturday
        #expect(result["Fay"] == .free(minutes: nil))
        #expect(result["Eli"] == .notShared)
    }

    @Test func orderIsMutualThenFreeThenInClassThenNotShared() {
        let mine = [meeting(.tue, hm(11), hm(12, 15))]
        let friends = [
            FriendSchedule(id: "1", name: "Zed", meetings: []),
            FriendSchedule(id: "2", name: "Yan", meetings: [meeting(.tue, hm(12), hm(13))]),
            FriendSchedule(id: "3", name: "Xia", meetings: [meeting(.tue, hm(9), hm(10))]),
        ]
        let names = FriendsFreeNow.statuses(mine: mine, friends: friends, now: date(10, 13, 12, 30), calendar: utc).map(\.name)
        #expect(names == ["Xia", "Yan", "Zed"])
    }
}

