//
//  ComposeInviteSheet.swift
//  CampusSync
//
//  Post a plan. Everything is prefilled (see ComposeDraft.standard), so posting
//  is two taps: "+ Post", then "Post". Only friends the user added can be invited.
//

import SwiftUI

struct ComposeInviteSheet: View {
    @State var draft: ComposeDraft
    let friends: [FriendProfile]
    let onPost: (ComposeDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(AppClock.self) private var clock

    var body: some View {
        NavigationStack {
            Form {
                Section("Plan") {
                    TextField(draft.resolvedTitle, text: $draft.title)
                        .minTapTarget()
                    Picker("Where", selection: $draft.landmark) {
                        ForEach(Landmark.allCases) { landmark in
                            Label(landmark.displayName, systemImage: landmark.symbol).tag(landmark)
                        }
                    }
                    .minTapTarget()
                }

                Section("Category") {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                        ForEach(InviteCategory.allCases) { category in
                            Button {
                                draft.category = category
                            } label: {
                                CategoryPill(category: category, isSelected: draft.category == category)
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(draft.category == category ? .isSelected : [])
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
                }

                Section("When") {
                    DatePicker("Starts", selection: $draft.startTime, in: clock.now...)
                        .minTapTarget()
                    Picker("Lasts", selection: $draft.durationMinutes) {
                        ForEach(ComposeDraft.durationOptions, id: \.self) { minutes in
                            Text(minutes.durationString).tag(minutes)
                        }
                    }
                    .minTapTarget()
                }

                Section {
                    ForEach(friends) { friend in
                        Toggle(friend.displayName, isOn: recipientBinding(for: friend.id))
                            .minTapTarget()
                    }
                } header: {
                    Text("Invite")
                } footer: {
                    Text(draft.canPost
                         ? "Only the friends you pick will see this plan."
                         : "Pick at least one friend to invite.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.screenBackground)
            .navigationTitle("New plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Post") {
                        onPost(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!draft.canPost)
                }
            }
        }
    }

    private func recipientBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { draft.recipientIDs.contains(id) },
            set: { isOn in
                if isOn { draft.recipientIDs.insert(id) } else { draft.recipientIDs.remove(id) }
            }
        )
    }
}

#Preview {
    let now = AppClock().now
    return ComposeInviteSheet(
        draft: ComposeDraft.standard(now: now, friendIDs: SampleData.friends().map(\.id)),
        friends: SampleData.friends(),
        onPost: { _ in }
    )
    .environment(AppClock())
}
