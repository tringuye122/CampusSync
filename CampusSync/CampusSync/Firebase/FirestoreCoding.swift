//
//  FirestoreCoding.swift
//  CampusSync
//
//  Converts between the app's models and Firestore documents. Field names match
//  firebase/firestore.rules exactly (the rules check exact keys), so change both together.
//

import FirebaseFirestore
import Foundation

enum FirestoreCoding {
    // MARK: Invites  (invites/{id})

    static func data(for invite: OpenInvite) -> [String: Any] {
        [
            "title": invite.title,
            "landmark": invite.landmark.rawValue,
            "category": invite.category.rawValue,
            "startTime": Timestamp(date: invite.startTime),
            "expiresAt": Timestamp(date: invite.expiresAt),
            "hostID": invite.hostID,
            "hostName": invite.hostName,
            "attendeeIDs": invite.attendeeIDs,
            "recipientIDs": invite.recipientIDs,
            "capacity": invite.capacity,
        ]
    }

    /// Nil when the document is malformed, so one bad document never breaks the feed.
    static func invite(id: String, data: [String: Any]) -> OpenInvite? {
        guard let title = data["title"] as? String,
              let landmark = (data["landmark"] as? String).flatMap(Landmark.init(rawValue:)),
              let category = (data["category"] as? String).flatMap(InviteCategory.init(rawValue:)),
              let start = (data["startTime"] as? Timestamp)?.dateValue(),
              let expires = (data["expiresAt"] as? Timestamp)?.dateValue(),
              let hostID = data["hostID"] as? String,
              let hostName = data["hostName"] as? String
        else { return nil }
        return OpenInvite(
            id: id, title: title, landmark: landmark, category: category,
            startTime: start, expiresAt: expires, hostID: hostID, hostName: hostName,
            attendeeIDs: data["attendeeIDs"] as? [String] ?? [],
            recipientIDs: data["recipientIDs"] as? [String] ?? [],
            capacity: data["capacity"] as? Int ?? 8)
    }

    // MARK: Shared schedule  (schedules/{uid}/meetings/{n})
    //
    // Times and a building only. Never a title, instructor, name or ID. The rules
    // reject any other key.

    static func data(for meeting: ClassMeeting) -> [String: Any] {
        [
            "courseCode": meeting.courseCode,
            "weekdays": meeting.weekdays.map(\.rawValue),
            "startMinutes": meeting.startMinutes,
            "endMinutes": meeting.endMinutes,
            "building": meeting.building,
        ]
    }

    static func meeting(data: [String: Any]) -> ClassMeeting? {
        guard let code = data["courseCode"] as? String,
              let days = data["weekdays"] as? [Int],
              let start = data["startMinutes"] as? Int,
              let end = data["endMinutes"] as? Int,
              let building = data["building"] as? String
        else { return nil }
        let weekdays = days.compactMap(Weekday.init(rawValue:))
        guard !weekdays.isEmpty else { return nil }
        return ClassMeeting(courseCode: code, weekdays: weekdays, startMinutes: start, endMinutes: end, building: building)
    }

    // MARK: Clubs  (clubs/{id}, clubs/{id}/events/{id})

    static func club(id: String, data: [String: Any]) -> Club? {
        guard let name = data["name"] as? String,
              let access = (data["access"] as? String).flatMap(ClubAccess.init(rawValue:))
        else { return nil }
        return Club(
            id: id, name: name, summary: data["summary"] as? String ?? "",
            symbol: data["symbol"] as? String ?? "person.3.fill",
            access: access, duesAmount: data["duesAmount"] as? Int ?? 0)
    }

    static func event(id: String, clubID: String, clubName: String, data: [String: Any]) -> ClubEvent? {
        guard let title = data["title"] as? String,
              let start = (data["startTime"] as? Timestamp)?.dateValue()
        else { return nil }
        return ClubEvent(
            id: id, clubID: clubID, clubName: clubName, title: title,
            details: data["details"] as? String ?? "", location: data["location"] as? String ?? "",
            startTime: start,
            endTime: (data["endTime"] as? Timestamp)?.dateValue(),   // nil: an hour after the start
            access: (data["access"] as? String).flatMap(ClubAccess.init(rawValue:)) ?? .public,
            duesAmount: data["duesAmount"] as? Int ?? 0)
    }
}
