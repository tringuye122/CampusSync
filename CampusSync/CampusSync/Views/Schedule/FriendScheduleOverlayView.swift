//
//  FriendScheduleOverlayView.swift
//  CampusSync
//
//  Schedule > Friends. Pick one friend (each avatar shows their longest shared free time on the
//  chosen day), then see "You" and the friend side by side on one timeline. Mutual free time is
//  outlined across both columns; tap a window to make an invite for it. The friend's blocks say
//  only "Class": they share meeting times, never course names.
//

import SwiftUI

struct FriendScheduleOverlayView: View {
    @Binding var day: Weekday
    @Environment(AppServices.self) private var services
    @Environment(AppClock.self) private var clock
    @Environment(AppRouter.self) private var router
    @State private var viewModel = FriendOverlapViewModel()
    @State private var isAddingFriends = false
    @State private var friendToRemove: FriendProfile?

    var body: some View {
        VStack(spacing: 12) {
            // The row (with the + tile) is always there: it is how you add the first friend.
            friendPicker
            switch viewModel.state {
            case .noFriends:
                message("No friends yet", "person.2.fill",
                        "Tap + to find a friend by their handle, then compare schedules here.")
            case .noOwnSchedule:
                message("Add your schedule first", "calendar.badge.plus",
                        "Import your ConnectCarolina PDF or load the demo schedule in Classes.")
            case .friendHasNoSchedule(let name):
                message("\(name) hasn't shared a schedule", "calendar.badge.exclamationmark",
                        "They may not have imported one yet, or they turned off sharing.")
            case .ready:
                DayChips(selection: $day).padding(.horizontal, 16)
                timeline
            }
        }
        .sheet(isPresented: $isAddingFriends, onDismiss: { Task { await reload() } }) {
            AddFriendsSheet()
        }
        .confirmationDialog(
            "Remove \(friendToRemove?.displayName ?? "friend")?",
            isPresented: Binding(get: { friendToRemove != nil }, set: { if !$0 { friendToRemove = nil } }),
            titleVisibility: .visible
        ) {
            Button("Unfriend", role: .destructive) {
                if let friend = friendToRemove { Task { await viewModel.unfriend(friend, services: services) } }
            }
        } message: {
            Text("You will stop seeing each other's schedules.")
        }
        .onAppear { Task { await reload() } }
        .onChange(of: services.sync.changeCount) { Task { await reload() } }
        .onChange(of: router.focusedFriendID) { Task { await reload() } }
        .onChange(of: day) { _, newDay in viewModel.selectedDay = newDay }
        .sheet(isPresented: Binding(
            get: { viewModel.composeDraft != nil },
            set: { if !$0 { viewModel.composeDraft = nil } }
        )) {
            if let draft = viewModel.composeDraft {
                ComposeInviteSheet(draft: draft, friends: viewModel.selectedFriend.map { [$0] } ?? []) { posted in
                    Task {
                        if await viewModel.post(posted, services: services) {
                            router.selectedTab = .invites   // show the new invite in the feed
                        }
                    }
                }
                .presentationDetents([.large])
            }
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private func reload() async {
        viewModel.selectedDay = day
        await viewModel.load(services: services, focus: router.focusedFriendID)
        router.focusedFriendID = nil   // a Home card's choice applies once
    }

    // MARK: Friend picker

    private var friendPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                addTile
                ForEach(viewModel.friends) { friend in
                    let isSelected = friend.id == viewModel.selectedFriendID
                    Button { viewModel.selectedFriendID = friend.id } label: {
                        VStack(spacing: 4) {
                            Avatar(name: friend.displayName, size: 60, isRinged: isSelected)
                            Text(firstName(friend))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text(longestText(for: friend))
                                .font(.footnote)
                                .foregroundStyle(Theme.textPrimary.opacity(0.85))
                        }
                        .frame(minWidth: 64)
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(friend.displayName), \(longestText(for: friend, spoken: true)) on \(day.fullName)")
                    .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
                    .contextMenu {
                        Button("Unfriend", systemImage: "person.badge.minus", role: .destructive) { friendToRemove = friend }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }

    /// The first tile in the row: opens the Add friends sheet. A red count shows waiting requests.
    private var addTile: some View {
        Button { isAddingFriends = true } label: {
            VStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 60, height: 60)
                    .background(Theme.pillBackground, in: Circle())
                    .overlay(Circle().strokeBorder(Theme.carolinaBlue, style: StrokeStyle(lineWidth: 2.5, dash: [5, 5])))
                    .overlay(alignment: .topTrailing) {
                        if viewModel.pendingRequestCount > 0 {
                            Text("\(viewModel.pendingRequestCount)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(Color.white)
                                .frame(minWidth: 22, minHeight: 22)
                                .background(Theme.ratingPoor, in: Capsule())
                                .offset(x: 6, y: -4)
                        }
                    }
                Text("Add")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            .frame(minWidth: 64)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(viewModel.pendingRequestCount > 0
                            ? "Add friends, \(viewModel.pendingRequestCount) waiting requests"
                            : "Add friends")
    }

    private func firstName(_ friend: FriendProfile) -> String {
        friend.displayName.split(separator: " ").first.map(String.init) ?? friend.displayName
    }

    private func longestText(for friend: FriendProfile, spoken: Bool = false) -> String {
        guard let window = viewModel.longestWindow(with: friend, on: day) else {
            return friend.classes.isEmpty ? "no schedule" : (spoken ? "no shared free time" : "none")
        }
        return window.durationMinutes.spacedDuration
    }

    // MARK: Timeline

    private var timeline: some View {
        let now = clock.now
        let isToday = Weekday(rawValue: Calendar.current.component(.weekday, from: now)) == day
        let friendName = viewModel.selectedFriend.map(firstName) ?? "Friend"
        let windows = viewModel.windows(on: day)
        return VStack(spacing: 8) {
            TimelineGrid(nowMinutes: isToday ? now.minutesSinceMidnight() : nil, columnTitles: ["You", friendName]) { metrics in
                GeometryReader { proxy in
                    let gap: CGFloat = 8
                    let columnWidth = (proxy.size.width - gap) / 2
                    ZStack(alignment: .topLeading) {
                        columnTrack(width: columnWidth, height: metrics.totalHeight, x: 0)
                        columnTrack(width: columnWidth, height: metrics.totalHeight, x: columnWidth + gap)
                        ForEach(viewModel.myMeetings(on: day), id: \.self) { meeting in
                            classBlock(meeting, title: meeting.courseCode, metrics: metrics, width: columnWidth, x: 0)
                        }
                        ForEach(viewModel.friendMeetings(on: day), id: \.self) { meeting in
                            classBlock(meeting, title: "Class", metrics: metrics, width: columnWidth, x: columnWidth + gap)
                        }
                        ForEach(windows) { window in
                            windowBlock(window, metrics: metrics, width: proxy.size.width)
                        }
                    }
                }
            }
            if windows.isEmpty {
                Text("No shared free time on \(day.fullName).")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func columnTrack(width: CGFloat, height: CGFloat, x: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(Theme.hairline.opacity(0.7), lineWidth: 1.5)
            .frame(width: width, height: height)
            .offset(x: x)
            .accessibilityHidden(true)
    }

    private func classBlock(_ meeting: ClassMeeting, title: String, metrics: TimelineMetrics, width: CGFloat, x: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title).font(.subheadline.weight(.heavy))
            Text(FreeWindowSummary.rangeWithPeriod(meeting.startMinutes, meeting.endMinutes)).font(.caption)
        }
        .foregroundStyle(Theme.navy)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(width: width - 4, alignment: .topLeading)
        .frame(height: max(34, metrics.height(from: meeting.startMinutes, to: meeting.endMinutes) - 3), alignment: .top)
        .background(Theme.carolinaBlue, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .clipped()
        .offset(x: x + 2, y: metrics.y(meeting.startMinutes) + 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(meeting.startMinutes.clockString) to \(meeting.endMinutes.clockString)")
    }

    /// Both free: a dotted box across both columns. Tapping it starts an invite for that time.
    private func windowBlock(_ window: OverlapWindow, metrics: TimelineMetrics, width: CGFloat) -> some View {
        Button {
            viewModel.startInvite(for: window, now: clock.now)
        } label: {
            Text(window.durationMinutes.spacedDuration)
                .font(.headline.weight(.bold))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                // Same dotted outline as the Timetable's free blocks.
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.carolinaBlue, style: StrokeStyle(lineWidth: 2.5, dash: [5, 5])))
        }
        .buttonStyle(.plain)
        .frame(width: width, height: max(30, metrics.height(from: window.startMinutes, to: window.endMinutes) - 3))
        .offset(y: metrics.y(window.startMinutes) + 1)
        .accessibilityLabel(
            "Both free \(window.durationMinutes.spacedDuration), \(window.startMinutes.clockString) to \(window.endMinutes.clockString)")
        .accessibilityHint("Opens a new invite for this time")
    }

    private func message(_ title: String, _ symbol: String, _ detail: String) -> some View {
        ContentUnavailableView(title, systemImage: symbol, description: Text(detail).foregroundStyle(Theme.textPrimary))
    }
}

#Preview {
    @Previewable @State var day = Weekday.tue
    return FriendScheduleOverlayView(day: $day)
        .environment(AppServices.preview())
        .environment(AppClock())
        .environment(AppRouter())
        .background(Theme.screenBackground)
}
