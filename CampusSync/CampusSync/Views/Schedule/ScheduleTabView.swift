//
//  ScheduleTabView.swift
//  CampusSync
//
//  My Schedule shows the weekly timetable, with a toolbar button to import the
//  ConnectCarolina PDF. Friend Overlap arrives in Phase 7.
//

import SwiftUI
import UniformTypeIdentifiers

struct ScheduleTabView: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case mySchedule = "My Schedule"
        case friendOverlap = "Friend Overlap"
        var id: String { rawValue }
    }

    @Environment(AppServices.self) private var services
    @Environment(AppClock.self) private var clock
    @State private var viewModel = ScheduleViewModel()
    @State private var importModel = ImportViewModel()
    @State private var mode: Mode = .mySchedule
    @State private var isPickingFile = false

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
            // Reload when sync mirrors new data into the cache.
            .onChange(of: services.sync.changeCount) { Task { await viewModel.load(from: services.schedule) } }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isPickingFile = true
                    } label: {
                        Label("Import PDF", systemImage: "square.and.arrow.down")
                    }
                    .accessibilityHint("Imports your ConnectCarolina class schedule")
                }
            }
            .fileImporter(isPresented: $isPickingFile, allowedContentTypes: [.pdf]) { result in
                switch result {
                case .success(let url):
                    Task {
                        // The Dates field has no year; the parser reads it from the PDF's term
                        // and uses this only if the term line is missing.
                        let year = Calendar.current.component(.year, from: clock.now)
                        await importModel.importPDF(at: url, using: ConnectCarolinaPDFParser(fallbackYear: year))
                    }
                case .failure:
                    importModel.errorMessage = "Couldn't open that file."
                }
            }
            .sheet(isPresented: $importModel.isReviewing) {
                ImportReviewView(viewModel: importModel) {
                    Task { await viewModel.load(from: services.schedule) }
                }
            }
            .sheet(item: $viewModel.selectedClass) { item in
                ProfessorRatingSheet(classSchedule: item)
                    .presentationDetents([.medium, .large])
            }
            .overlay {
                if importModel.isParsing { ProgressView("Reading PDF…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) }
            }
            .alert(
                "Import problem",
                isPresented: Binding(
                    get: { importModel.errorMessage != nil },
                    set: { if !$0 { importModel.errorMessage = nil } }
                )
            ) {
                Button("Load demo schedule") {
                    Task { await viewModel.loadDemoSchedule(using: services) }
                }
                Button("OK", role: .cancel) {}
            } message: {
                Text(importModel.errorMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private var mySchedule: some View {
        if viewModel.isEmpty {
            ContentUnavailableView {
                Label("No classes yet", systemImage: "calendar.badge.plus")
            } description: {
                Text("Import your ConnectCarolina class schedule PDF, or load the demo schedule.")
            } actions: {
                Button("Import PDF") { isPickingFile = true }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.carolinaBlue)
                    .foregroundStyle(Theme.navy)
                    .minTapTarget()
                Button("Load demo schedule") {
                    Task { await viewModel.loadDemoSchedule(using: services) }
                }
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
