//
//  ScheduleTabView.swift
//  CampusSync
//
//  Three segments under the profile header: Timetable (one day at a time), Friends (you and one
//  friend side by side, with mutual free time outlined) and Classes (cards with inline ratings).
//  The ConnectCarolina PDF import lives in Classes and in the empty states.
//

import SwiftUI
import UniformTypeIdentifiers

struct ScheduleTabView: View {
    @Environment(AppServices.self) private var services
    @Environment(AppClock.self) private var clock
    @Environment(AppRouter.self) private var router
    @State private var viewModel = ScheduleViewModel()
    @State private var importModel = ImportViewModel()
    @State private var day = Weekday.mon
    @State private var isPickingFile = false

    var body: some View {
        @Bindable var router = router
        VStack(spacing: 12) {
            SegmentedTabs(values: ScheduleSegment.allCases, selection: $router.scheduleSegment) { $0.rawValue }
                .padding(.horizontal, 16)
                .padding(.top, 12)

            switch router.scheduleSegment {
            case .timetable:
                timetable
            case .friends:
                FriendScheduleOverlayView(day: $day)
            case .classes:
                if viewModel.isEmpty { emptyState } else { classes }
            }
        }
        .withAppHeader()
        .onAppear {
            day = DayChips.initialDay(now: clock.now)
            Task { await reload() }
        }
        // Reload when sync mirrors new data into the cache, or after a local write.
        .onChange(of: services.sync.changeCount) { Task { await reload() } }
        .onChange(of: services.dataVersion) { Task { await reload() } }
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
                Task { await reload() }
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

    private func reload() async {
        await viewModel.load(from: services.schedule)
        await viewModel.loadRatings(from: services.schedule)
    }

    // MARK: Segments

    @ViewBuilder
    private var timetable: some View {
        if viewModel.isEmpty {
            emptyState
        } else {
            DayChips(selection: $day).padding(.horizontal, 16)
            TimetableView(viewModel: viewModel, day: day)
        }
    }

    private var classes: some View {
        ClassesListView(
            viewModel: viewModel,
            onImport: { isPickingFile = true },
            onLoadDemo: { Task { await viewModel.loadDemoSchedule(using: services) } })
    }

    private var emptyState: some View {
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
    }
}

#Preview {
    ScheduleTabView()
        .environment(AppServices.preview())
        .environment(AppClock())
        .environment(AppRouter())
        .environment(AuthService(backend: MockAuthBackend(), defaults: UserDefaults(suiteName: "preview-auth")!))
}

#Preview("Friends · Tuesday") {
    let router = AppRouter()
    router.scheduleSegment = .friends
    return ScheduleTabView()
        .environment(AppServices.preview())
        .environment(AppClock())
        .environment(router)
        .environment(AuthService(backend: MockAuthBackend(), defaults: UserDefaults(suiteName: "preview-auth")!))
}

#Preview("Classes") {
    let router = AppRouter()
    router.scheduleSegment = .classes
    return ScheduleTabView()
        .environment(AppServices.preview())
        .environment(AppClock())
        .environment(router)
        .environment(AuthService(backend: MockAuthBackend(), defaults: UserDefaults(suiteName: "preview-auth")!))
}
