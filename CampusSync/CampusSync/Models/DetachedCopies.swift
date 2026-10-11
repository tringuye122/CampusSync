//
//  DetachedCopies.swift
//  CampusSync
//
//  Plain copies of SwiftData models that are not in any context. A screen that keeps a live
//  @Model object across a reload dies with a fatal error ("backing data was detached") the moment
//  that object is deleted (a Reset, an unfriend, an invite its host removed, a cache wipe) and the
//  screen draws it once more before it reloads. View models therefore keep these copies, which
//  stay readable for as long as the screen holds them. Writes still go through repositories by id.
//

import Foundation

extension OpenInvite {
    var detachedCopy: OpenInvite {
        OpenInvite(
            id: id, title: title, landmark: landmark, category: category, startTime: startTime,
            expiresAt: expiresAt, hostID: hostID, hostName: hostName, attendeeIDs: attendeeIDs,
            recipientIDs: recipientIDs, capacity: capacity)
    }
}

extension FriendProfile {
    var detachedCopy: FriendProfile {
        FriendProfile(id: id, displayName: displayName, classes: classes)
    }
}

extension Club {
    var detachedCopy: Club {
        Club(id: id, name: name, summary: summary, symbol: symbol, access: access, duesAmount: duesAmount)
    }
}

extension ClassSchedule {
    var detachedCopy: ClassSchedule {
        ClassSchedule(
            id: id, courseCode: courseCode, title: title, section: section, units: units, weekdays: weekdays,
            startMinutes: startMinutes, endMinutes: endMinutes, building: building, room: room,
            startDate: startDate, endDate: endDate, instructors: instructors, professor: professor)
    }
}
