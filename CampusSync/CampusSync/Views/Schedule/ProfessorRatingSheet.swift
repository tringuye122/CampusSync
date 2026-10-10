//
//  ProfessorRatingSheet.swift
//  CampusSync
//
//  Opens when a class block is tapped. Ratings are invented mock values, so the
//  sheet always carries a visible "Demo data" footer. The person shown is the
//  first-listed instructor, labelled "Instructor".
//

import SwiftUI

struct ProfessorRatingSheet: View {
    let classSchedule: ClassSchedule
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if let info = classSchedule.professor {
                        stats(info)
                        tags(info)
                    } else {
                        Text("No rating available for this instructor.")
                            .foregroundStyle(.secondary)
                            .cardStyle()
                    }
                    demoFooter
                }
                .padding(16)
            }
            .background(Theme.screenBackground)
            .navigationTitle(classSchedule.courseCode)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .minTapTarget()
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(classSchedule.title)
                .font(.title2.bold())
                .foregroundStyle(Theme.textPrimary)
            // Label is "Instructor" on purpose: the field can include co-instructors and TAs.
            if let name = classSchedule.primaryInstructor {
                Label("Instructor: \(name)", systemImage: "person.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
            } else {
                Label("Instructor: not listed", systemImage: "person.fill")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            Text("\(classSchedule.building) \(classSchedule.room)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func stats(_ info: ProfessorInfo) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
            StatTile(value: String(format: "%.1f", info.overallRating), unit: "/ 5",
                     label: "Overall", symbol: "star.fill")
            StatTile(value: String(format: "%.1f", info.difficulty), unit: "/ 5",
                     label: "Difficulty", symbol: "gauge.with.dots.needle.67percent")
            StatTile(value: "\(info.wouldTakeAgainPercent)", unit: "%",
                     label: "Would take again", symbol: "arrow.counterclockwise")
        }
    }

    private func tags(_ info: ProfessorInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Top tags")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            FlowLayout {
                ForEach(info.topTags, id: \.self) { tag in
                    Text(tag)
                        .font(.subheadline)
                        .foregroundStyle(Theme.navy)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Theme.carolinaBlue.opacity(0.35), in: Capsule())
                }
            }
        }
    }

    private var demoFooter: some View {
        Label("Demo data: ratings are invented for this demo and are not real RateMyProfessor scores.",
              systemImage: "info.circle")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }
}

private struct StatTile: View {
    let value: String
    let unit: String
    let label: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(Theme.textPrimary)
                .accessibilityHidden(true)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.title.bold())
                Text(unit).font(.subheadline).foregroundStyle(.secondary)
            }
            .foregroundStyle(Theme.textPrimary)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): \(value) \(unit)")
    }
}

#Preview {
    ProfessorRatingSheet(classSchedule: SampleData.classes()[1])
}
