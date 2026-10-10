//
//  PlaceholderView.swift
//  CampusSync
//
//  Stand-in content for tabs whose real screens arrive in a later phase.
//

import SwiftUI

struct PlaceholderView: View {
    let title: String
    let symbol: String
    let message: String

    var body: some View {
        NavigationStack {
            ContentUnavailableView(title, systemImage: symbol, description: Text(message))
                .background(Theme.screenBackground)
                .navigationTitle(title)
        }
    }
}

#Preview {
    PlaceholderView(title: "Clubs", symbol: "person.3.fill", message: "Coming in a later phase.")
}
