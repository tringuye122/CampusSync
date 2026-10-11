//
//  ComposeClubEventSheet.swift
//  CampusSync
//
//  Post an event for a club you joined. The event takes that club's name, access and dues.
//

import SwiftUI

struct ComposeClubEventSheet: View {
    let clubs: [Club]
    /// Returns true when the event was posted. The sheet stays open (with the draft) until then.
    let onPost: (ClubEventDraft) async -> Bool

    @State private var draft: ClubEventDraft
    @State private var isPosting = false
    @State private var postFailed = false
    @Environment(\.dismiss) private var dismiss
    @Environment(AppClock.self) private var clock

    init(clubs: [Club], now: Date, onPost: @escaping (ClubEventDraft) async -> Bool) {
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
                if postFailed {
                    Section {
                        Label("Couldn't post. Check your connection and try again.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
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
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(isPosting) }
                ToolbarItem(placement: .confirmationAction) {
                    if isPosting {
                        ProgressView()
                    } else {
                        Button("Post") { Task { await submit() } }
                            .fontWeight(.semibold)
                            .disabled(!draft.isValid || clubs.isEmpty)
                    }
                }
            }
        }
    }

    /// One post at a time; closes only once the post worked.
    private func submit() async {
        guard !isPosting else { return }
        isPosting = true
        postFailed = false
        defer { isPosting = false }
        if await onPost(draft) { dismiss() } else { postFailed = true }
    }
}

#Preview {
    ComposeClubEventSheet(clubs: SampleData.clubs(), now: AppClock().now, onPost: { _ in true })
        .environment(AppClock())
}
