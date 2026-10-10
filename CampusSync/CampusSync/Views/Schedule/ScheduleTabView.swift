//
//  ScheduleTabView.swift
//  CampusSync
//
//  My Schedule shows the weekly timetable. Friend Overlap arrives in Phase 7;
//  the PDF import button arrives in Phase 6.
//

import SwiftUI

struct ScheduleTabView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case mySchedule = "My Schedule"
        case friendOverlap = "Friend Overlap"
        var id: String { rawValue }
    }

    @Environment(AppServices.self) private var services
    @State private var viewModel = ScheduleViewModel()
    @State private var mode: Mode = .mySchedule

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("View", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                switch mode {
                case .mySchedule:
                    mySchedule
                case .friendOverlap:
                    ContentUnavailableView(
                        "Friend Overlap",
                        systemImage: "person.2.fill",
                        description: Text("Compare schedules with a friend to find mutual free time. Coming soon.")
                    )
                }
            }
            .background(Theme.screenBackground)
            .navigationTitle("Schedule")
            .onAppear { Task { await viewModel.load(from: services.schedule) } }
            .sheet(item: $viewModel.selectedClass) { item in
                ProfessorRatingSheet(classSchedule: item)
                    .presentationDetents([.medium, .large])
            }
        }
    }

    @ViewBuilder
    private var mySchedule: some View {
        if viewModel.isEmpty {
            ContentUnavailableView {
                Label("No classes yet", systemImage: "calendar.badge.plus")
            } description: {
                Text("Load the demo schedule to see how the timetable looks.")
            } actions: {
                Button("Load demo schedule") {
                    Task { await viewModel.loadDemoSchedule(using: services.schedule) }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.carolinaBlue)
                .foregroundStyle(Theme.navy)
                .minTapTarget()
            }
        } else {
            TimetableView(viewModel: viewModel)
        }
    }
}

#Preview {
    ScheduleTabView()
        .environment(AppServices.preview())
        .environment(AppClock())
}
