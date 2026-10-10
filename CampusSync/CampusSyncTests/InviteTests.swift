//
//  InviteTests.swift
//  CampusSyncTests
//

import Foundation
import SwiftData
import Testing
@testable import CampusSync

@MainActor
struct InviteTests {
    private let calendar = Calendar.current

    /// Tuesday, Oct 13 2026, 12:30 PM local.
    private var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 12, minute: 30))!
    }

    private func minutes(_ value: Int) -> Date { now.addingTimeInterval(TimeInterval(value * 60)) }

    private func invite(start: Int, expires: Int, host: String = SampleData.mayaID) -> OpenInvite {
        OpenInvite(title: "T", landmark: .thePit, category: .social, startTime: minutes(start),
                   expiresAt: minutes(expires), hostID: host, hostName: "H")
    }

    // MARK: Sections

    @Test func invitesGroupByTimeAndExpiredOnesDisappear() {
        let invites = [
            invite(start: -10, expires: 50),    // happening now
            invite(start: 20, expires: 80),     // starting soon
            invite(start: 120, expires: 200),   // later today
            invite(start: 24 * 60, expires: 24 * 60 + 60), // tomorrow
            invite(start: -120, expires: -1),   // expired
        ]
        let sections = InviteTiming.sections(for: invites, now: now, calendar: calendar)
        #expect(sections.map(\.kind) == [.happeningNow, .startingSoon, .laterToday, .upcoming])
        #expect(sections.flatMap(\.invites).count == 4)
    }

    @Test func inviteExpiresExactlyAfterExpiresAt() {
        let one = invite(start: 0, expires: 30)
        #expect(!one.isExpired(at: minutes(30)))
        #expect(one.isExpired(at: minutes(30).addingTimeInterval(1)))
    }

    @Test func countdownTextDescribesTheState() {
        let soon = InviteTiming.countdownText(start: minutes(20), expiresAt: minutes(80), now: now, calendar: calendar)
        #expect(soon == "Starts in 20 min")
        let live = InviteTiming.countdownText(start: minutes(-10), expiresAt: minutes(50), now: now, calendar: calendar)
        #expect(live == "Happening now · ends in 50 min")
    }

    // MARK: Compose draft

    @Test func standardDraftIsReadyToPostInTwoTaps() {
        let friends = SampleData.friends().map(\.id)
        let draft = ComposeDraft.standard(now: now, friendIDs: friends)
        #expect(draft.canPost)
        #expect(draft.recipientIDs == Set(friends))
        let lead = draft.startTime.timeIntervalSince(now)
        #expect(lead >= 15 * 60 && lead < 20 * 60)
        #expect(draft.startTime.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 300) == 0)
        #expect(draft.resolvedTitle == "Social at The Pit")
    }

    @Test func makeInviteSetsAbsoluteExpiryAndHostAttends() {
        var draft = ComposeDraft.standard(now: now, friendIDs: [SampleData.mayaID])
        draft.title = "  Study  "
        draft.durationMinutes = 90
        let made = draft.makeInvite(hostID: SampleData.userID, hostName: "Tri")
        #expect(made.title == "Study")
        #expect(made.expiresAt == draft.startTime.addingTimeInterval(90 * 60))
        #expect(made.attendeeIDs == [SampleData.userID])
        #expect(made.recipientIDs == [SampleData.mayaID])
    }

    @Test func draftWithNoRecipientsCannotPost() {
        var draft = ComposeDraft.standard(now: now, friendIDs: [SampleData.mayaID])
        draft.recipientIDs = []
        #expect(!draft.canPost)
    }

    // MARK: View model against the local repositories

    @Test func postedInviteAppearsOnlyForChosenFriendsAndHost() async throws {
        let container = SampleData.previewContainer(now: now)
        let services = AppServices(context: container.mainContext, retaining: container)
        let model = InvitesViewModel()
        await model.load(services: services, now: now)

        var draft = model.standardDraft(now: now)
        draft.title = "Board games"
        draft.recipientIDs = [SampleData.mayaID]
        let saved = await model.post(draft, services: services, now: now)
        #expect(saved)

        // The host (the demo user) sees the new plan alongside the 6 seeded ones.
        #expect(model.sections(at: now).flatMap(\.invites).count == 7)
        #expect(model.invites.contains { $0.title == "Board games" && $0.hostID == SampleData.userID })
    }

    @Test func inviteNotAddressedToUserIsHidden() async throws {
        let container = SampleData.previewContainer(now: now)
        let services = AppServices(context: container.mainContext, retaining: container)
        let hidden = invite(start: 30, expires: 90, host: SampleData.mayaID)
        hidden.recipientIDs = [SampleData.samID]
        try await services.invites.post(hidden)
        let visible = try await services.invites.activeInvites(now: now)
        #expect(!visible.contains { $0.id == hidden.id })
    }
}
