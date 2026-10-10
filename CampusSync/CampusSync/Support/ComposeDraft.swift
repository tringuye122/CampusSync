//
//  ComposeDraft.swift
//  CampusSync
//
//  The compose sheet's working state. Defaults make posting a two-tap action:
//  everything is prefilled, so tap "+ Post", then "Post".
//

import Foundation

struct ComposeDraft: Equatable {
    var title = ""
    var landmark: Landmark = .thePit
    var category: InviteCategory = .social
    var startTime: Date
    var durationMinutes = 60
    /// Friends who get the invite. The poster picks; all friends are preselected.
    var recipientIDs: Set<UUID>

    static let durationOptions = [30, 60, 90, 120]
    static let defaultLeadMinutes = 15
    static let capacity = 8

    /// Starts about 15 minutes from `now`, rounded up to a 5 minute mark.
    static func standard(now: Date, friendIDs: [UUID]) -> ComposeDraft {
        let target = now.addingTimeInterval(TimeInterval(defaultLeadMinutes * 60))
        let rounded = (target.timeIntervalSinceReferenceDate / 300).rounded(.up) * 300
        return ComposeDraft(
            startTime: Date(timeIntervalSinceReferenceDate: rounded),
            recipientIDs: Set(friendIDs)
        )
    }

    /// Blank titles fall back to "Social at The Pit" so a one-tap post still reads well.
    var resolvedTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "\(category.displayName) at \(landmark.displayName)" : trimmed
    }

    /// The invite needs at least one recipient.
    var canPost: Bool { !recipientIDs.isEmpty }

    /// `expiresAt` is an absolute date: start plus duration. The poster attends automatically.
    func makeInvite(hostID: UUID, hostName: String) -> OpenInvite {
        OpenInvite(
            title: resolvedTitle,
            landmark: landmark,
            category: category,
            startTime: startTime,
            expiresAt: startTime.addingTimeInterval(TimeInterval(durationMinutes * 60)),
            hostID: hostID,
            hostName: hostName,
            attendeeIDs: [hostID],
            recipientIDs: Array(recipientIDs),
            capacity: Self.capacity
        )
    }
}
