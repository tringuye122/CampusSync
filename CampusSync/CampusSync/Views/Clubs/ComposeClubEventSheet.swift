//
//  ComposeClubEventSheet.swift
//  CampusSync
//
//  Post an event for a club you joined. The event takes that club's name, access and dues.
//

import SwiftUI

struct ComposeClubEventSheet: View {
    let clubs: [Club]
    let onPost: (ClubEventDraft) -> Void

    @State private var draft: ClubEventDraft
    @Environment(\.dismiss) private var dismiss
    @Environment(AppClock.self) private var clock

    init(clubs: [Club], now: Date, onPost: @escaping (ClubEventDraft) -> Void) {
        self.clubs = clubs
        self.onPost = onPost
        // Prefilled: the first club, starting at the next whole hour.
        let calendar = Calendar.current
        let nextHour = calendar.nextDate(after: now, matching: DateComponents(minute: 0, second: 0), matchingPolicy: .nextTime) ?? now
        _draft = State(initialValue: ClubEventDraft(
            clubID: clubs.first?.id ?? "", title: "", location: "", start: nextHour))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Club") {
                    if clubs.isEmpty {
                        Text("Join a club first, then you can post its events.")
                            .foregroundStyle(Theme.textPrimary)
                    } else {
                        Picker("Club", selection: $draft.clubID) {
                            ForEach(clubs) { club in Text(club.name).tag(club.id) }
                        }
                        .minTapTarget()
                    }
                }
                Section("Event") {
                    TextField("Title", text: $draft.title).minTapTarget()
                    TextField("Where", text: $draft.location).minTapTarget()
                    TextField("Details (optional)", text: $draft.details, axis: .vertical)
                        .lineLimit(2...4)
                }
                Section("When") {
                    DatePicker("Starts", selection: $draft.start, in: clock.now...).minTapTarget()
                    Picker("Lasts", selection: $draft.durationMinutes) {
                        ForEach(ComposeDraft.durationOptions, id: \.self) { Text($0.durationString).tag($0) }
                    }
                    .minTapTarget()
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.screenBackground)
            .navigationTitle("New club event")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") {
                        onPost(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!draft.isValid || clubs.isEmpty)
                }
            }
        }
    }
}

#Preview {
    ComposeClubEventSheet(clubs: SampleData.clubs(), now: AppClock().now, onPost: { _ in })
        .environment(AppClock())
}
