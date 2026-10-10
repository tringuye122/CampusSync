//
//  ProfessorRatingSheet.swift
//  CampusSync
//
//  Opens when a class block is tapped. Shows the first-listed instructor's rating
//  from RateMyProfessors.com (fetched, cached, and credited; never invented).
//  The person shown is the first name in the Instructor field, which can also
//  list co-instructors and TAs.
//

import SwiftUI

struct ProfessorRatingSheet: View {
    let classSchedule: ClassSchedule

    @Environment(AppServices.self) private var services
    @Environment(\.dismiss) private var dismiss
    @State private var lookup: ProfessorRatingLookup?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    content
                    attribution
                }
                .padding(16)
            }
            .background(Theme.screenBackground)
            .navigationTitle(classSchedule.courseCode)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        lookup = nil
        guard let name = classSchedule.primaryInstructor else { return }
        lookup = await services.schedule.professorRating(for: name)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(classSchedule.title)
                .font(.title2.bold())
                .foregroundStyle(Theme.textPrimary)
            // Labelled "Instructor" on purpose: the field can include co-instructors and TAs.
            Label("Instructor: \(classSchedule.primaryInstructor ?? "not listed")", systemImage: "person.fill")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text("\(classSchedule.building) \(classSchedule.room)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var content: some View {
        if classSchedule.primaryInstructor == nil {
            message("No instructor is listed for this class.", symbol: "person.slash")
        } else {
            switch lookup {
            case nil:
                ProgressView("Looking up ratings…")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            case .found(let rating):
                ratingContent(rating)
            case .notFound:
                message("RateMyProfessors has no page for this instructor at UNC.", symbol: "magnifyingglass")
            case .unavailable:
                VStack(alignment: .leading, spacing: 12) {
                    message("Couldn't reach RateMyProfessors. Connect to the internet and try again.",
                            symbol: "wifi.slash")
                    Button("Try again") { Task { await load() } }
                        .buttonStyle(.bordered)
                        .minTapTarget()
                }
            }
        }
    }

    private func ratingContent(_ rating: ProfessorRating) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let department = rating.department {
                Text("\(rating.displayName) · \(department)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if rating.hasRatings {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 12) {
                    StatTile(value: String(format: "%.1f", rating.overallRating), unit: "/ 5",
                             label: "Overall", symbol: "star.fill")
                    StatTile(value: String(format: "%.1f", rating.difficulty), unit: "/ 5",
                             label: "Difficulty", symbol: "gauge.with.dots.needle.67percent")
                    StatTile(value: rating.wouldTakeAgainPercent.map { String(format: "%.0f", $0) } ?? "N/A",
                             unit: rating.wouldTakeAgainPercent == nil ? "" : "%",
                             label: "Would take again", symbol: "arrow.counterclockwise")
                }
                Text("Based on \(rating.numRatings) \(rating.numRatings == 1 ? "rating" : "ratings")")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                message("No ratings on RateMyProfessors yet.", symbol: "star")
            }

            if let url = rating.profileURL {
                Link(destination: url) {
                    Label("View on RateMyProfessors", systemImage: "arrow.up.right.square")
                        .frame(minHeight: Theme.minTapTarget)
                }
            }
        }
    }

    private func message(_ text: String, symbol: String) -> some View {
        Label(text, systemImage: symbol)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardStyle()
    }

    private var attribution: some View {
        Label("Ratings are from RateMyProfessors.com, matched by name. They are student opinions and may not describe your section.",
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
        .environment(AppServices.preview())
}
