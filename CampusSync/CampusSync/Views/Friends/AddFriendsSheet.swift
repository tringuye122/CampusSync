//
//  AddFriendsSheet.swift
//  CampusSync
//
//  The sheet behind the + tile on Schedule > Friends: search by handle, answer requests, see
//  who you asked, and manage friends, all without leaving the Schedule tab.
//

import SwiftUI

struct AddFriendsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            FriendsView()
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .presentationDetents([.large])
    }
}

#Preview {
    AddFriendsSheet()
        .environment(AppServices.preview())
}
