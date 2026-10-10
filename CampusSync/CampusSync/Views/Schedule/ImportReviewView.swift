//
//  ImportReviewView.swift
//  CampusSync
//
//  Shown after a PDF is parsed and before anything is saved. The student can fix
//  or remove classes the parser got wrong, then save.
//

import SwiftUI
import UniformTypeIdentifiers

struct ImportReviewView: View {
    let viewModel: ImportViewModel
    let onSaved: () -> Void

    @Environment(AppServices.self) private var services
    @State private var editing: ImportedClass?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(viewModel.drafts) { draft in
                        Button { editing = draft } label: { row(draft) }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button("Remove", role: .destructive) { viewModel.remove(draft) }
                            }
                    }
                } header: {
                    Text(headerText)
                } footer: {
                    Text("Tap a class to fix it, or swipe to remove it. Saving replaces your current schedule.")
                }

                if !viewModel.skipped.isEmpty {
                    Section("Left out") {
                        ForEach(viewModel.skipped, id: \.self) { note in
                            Label(note, systemImage: "exclamationmark.triangle")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.screenBackground)
            .navigationTitle("Review schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { viewModel.cancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if await viewModel.save(services: services) { onSaved() }
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(!viewModel.canSave)
                }
            }
            .sheet(item: $editing) { draft in
                ImportClassEditSheet(draft: draft) { viewModel.update($0) }
            }
        }
    }

    private var headerText: String {
        let count = viewModel.drafts.count
        let noun = count == 1 ? "class" : "classes"
        return [viewModel.termLabel, "\(count) \(noun)"].compactMap { $0 }.joined(separator: " · ")
    }

    private func row(_ draft: ImportedClass) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(draft.courseCode).font(.headline)
                Spacer()
                Image(systemName: "pencil").foregroundStyle(.secondary).accessibilityHidden(true)
            }
            Text(draft.title).font(.subheadline)
            Text("\(draft.weekdays.map(\.shortLabel).joined(separator: " ")) · \(draft.startMinutes.clockString) to \(draft.endMinutes.clockString)")
                .font(.footnote).foregroundStyle(.secondary)
            Text("\(draft.building) \(draft.room)".trimmingCharacters(in: .whitespaces))
                .font(.footnote).foregroundStyle(.secondary)
            if let instructor = draft.primaryInstructor {
                Text("Instructor: \(instructor)").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .foregroundStyle(Theme.textPrimary)
        .frame(minHeight: Theme.minTapTarget, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the editor")
    }
}

/// Editor for one parsed class: the fields the parser is most likely to get wrong.
struct ImportClassEditSheet: View {
    @State var draft: ImportedClass
    let onSave: (ImportedClass) -> Void

    @Environment(\.dismiss) private var dismiss

    /// Fixed reference day; only the hour and minute of the pickers matter.
    private static let referenceDay = Calendar.current.startOfDay(for: Date(timeIntervalSinceReferenceDate: 0))

    var body: some View {
        NavigationStack {
            Form {
                Section("Class") {
                    TextField("Title", text: $draft.title)
                    LabeledContent("Course", value: draft.courseCode)
                    TextField("Instructor", text: instructorBinding)
                }
                Section("Where") {
                    TextField("Building", text: $draft.building)
                    TextField("Room", text: $draft.room)
                }
                Section("When") {
                    ForEach(Weekday.allCases) { day in
                        Toggle(day.fullName, isOn: dayBinding(day))
                            .tint(Theme.success)
                    }
                    DatePicker("Starts", selection: timeBinding(\.startMinutes), displayedComponents: .hourAndMinute)
                    DatePicker("Ends", selection: timeBinding(\.endMinutes), displayedComponents: .hourAndMinute)
                }
                if !isValid {
                    Section {
                        Text("Pick at least one day, and make the end time later than the start.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.screenBackground)
            .navigationTitle(draft.courseCode)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onSave(draft)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(!isValid)
                }
            }
        }
    }

    private var isValid: Bool {
        !draft.weekdays.isEmpty && draft.endMinutes > draft.startMinutes
    }

    /// Edits the first-listed instructor (the one shown in the rating sheet).
    private var instructorBinding: Binding<String> {
        Binding(
            get: { draft.instructors.first ?? "" },
            set: { name in
                let trimmed = name.trimmingCharacters(in: .whitespaces)
                var rest = Array(draft.instructors.dropFirst())
                if draft.instructors.isEmpty { rest = [] }
                draft.instructors = trimmed.isEmpty ? rest : [trimmed] + rest
            }
        )
    }

    private func dayBinding(_ day: Weekday) -> Binding<Bool> {
        Binding(
            get: { draft.weekdays.contains(day) },
            set: { isOn in
                if isOn {
                    draft.weekdays = Weekday.allCases.filter { draft.weekdays.contains($0) || $0 == day }
                } else {
                    draft.weekdays.removeAll { $0 == day }
                }
            }
        )
    }

    private func timeBinding(_ keyPath: WritableKeyPath<ImportedClass, Int>) -> Binding<Date> {
        Binding(
            get: { Self.referenceDay.addingTimeInterval(TimeInterval(draft[keyPath: keyPath] * 60)) },
            set: { draft[keyPath: keyPath] = $0.minutesSinceMidnight() }
        )
    }
}

#Preview {
    let parsed = SampleData.classes().map { cls in
        ImportedClass(
            courseCode: cls.courseCode, title: cls.title, section: cls.section, units: cls.units,
            weekdays: cls.weekdays, startMinutes: cls.startMinutes, endMinutes: cls.endMinutes,
            building: cls.building, room: cls.room, startDate: cls.startDate, endDate: cls.endDate,
            instructors: cls.instructors)
    }
    let model = ImportViewModel()
    return ImportReviewView(viewModel: model, onSaved: {})
        .environment(AppServices.preview())
        .task { await model.importPDF(at: URL(fileURLWithPath: "/dev/null"), using: PreviewImporter(classes: parsed)) }
}

private struct PreviewImporter: ScheduleImporter {
    let classes: [ImportedClass]
    var supportedTypes: [UTType] { [.pdf] }
    func importSchedule(from url: URL) async throws -> ImportResult {
        ImportResult(term: "2026 Fall", classes: classes, skipped: ["ART 101: TBA has no usable time"])
    }
}
