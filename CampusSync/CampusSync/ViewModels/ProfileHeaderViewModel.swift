//
//  ProfileHeaderViewModel.swift
//  CampusSync
//
//  What the profile header needs beyond the signed-in account: whether the student is a
//  Verified Member (paid dues) and their recurring between-class gap.
//

import Foundation
import Observation

@Observable
final class ProfileHeaderViewModel {
    private(set) var isVerifiedMember = false
    private(set) var freeSummary: String?

    func load(services: AppServices) async {
        isVerifiedMember = (try? await services.users.currentUser().isVerifiedMember) ?? false
        let meetings = ((try? await services.schedule.classes()) ?? []).map(\.meeting)
        freeSummary = FreeWindowSummary.text(meetings: meetings)
    }
}
