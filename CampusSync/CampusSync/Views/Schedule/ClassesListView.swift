//
//  ClassesListView.swift
//  CampusSync
//
//  Schedule > Classes: one card per class with the first-listed instructor's RateMyProfessors
//  rating inline (rating, difficulty, would take again, number of ratings), so classes can be
//  compared at a glance. Ratings are fetched, cached and credited; never invented. If there is no
//  rating the card says so instead of showing numbers.
//

import SwiftUI

struct ClassesListView: View {
    let viewModel: ScheduleViewModel
    let onImport: () -> Void
    let onLoadDemo: () -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                Text("Ratings come from RateMyProfessors and are matched by instructor name, so they can be wrong or missing.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textPrimary.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .leading)

                ViewThatFits(in: .horizontal) {
                    HStack { importButton; demoButton; Spacer(minLength: 0) }
                    VStack(alignment: .leading, spacing: 4) { importButton; demoButton }
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                // Week order: Monday classes first, then by start time.
                ForEach(viewModel.classes.sorted {
                    ($0.weekdays.first?.rawValue ?? 9, $0.startMinutes) < ($1.weekdays.first?.rawValue ?? 9, $1.startMinutes)
                }) { cls in
                    Button { viewModel.selectedClass = cls } label: {
                        ClassCard(cls: cls, lookup: viewModel.rating(for: cls))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows more about this instructor")
                }
            }
            .padding(16)
        }
    }
}

private extension ClassesListView {
    var importButton: some View {
        Button("Import schedule PDF", action: onImport)
            .buttonStyle(.bordered)
            .tint(Theme.textPrimary)
            .minTapTarget()
    }

    var demoButton: some View {
        Button("Load demo schedule", action: onLoadDemo)
            .lineLimit(1)
            .minTapTarget()
    }
}

private struct ClassCard: View {
    let cls: ClassSchedule
    let lookup: ProfessorRatingLookup?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) { titleBlock; Spacer(minLength: 8); whenText }
                VStack(alignment: .leading, spacing: 2) { titleBlock; whenText }
            }
            Text(cls.title.uppercased())
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { instructorLabel; instructorStar; instructorName }
                VStack(alignment: .leading, spacing: 2) {
                    instructorLabel
                    HStack(spacing: 6) { instructorStar; instructorName }
                }
            }
            .foregroundStyle(Theme.textPrimary)
            .accessibilityElement(children: .combine)

            if cls.primaryInstructor != nil {
                RatingBand(lookup: lookup)
            }
        }
        .cardStyle()
        .accessibilityElement(children: .contain)
    }

    private var instructorLabel: some View {
        Text("Instructor").font(.subheadline.weight(.bold)).fixedSize()
    }

    @ViewBuilder
    private var instructorStar: some View {
        if let tone { Image(systemName: "star.fill").foregroundStyle(color(for: tone)) }
    }

    private var instructorName: some View {
        Text(cls.primaryInstructor ?? "Staff").font(.headline.weight(.bold))
    }

    private var titleBlock: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(cls.courseCode).font(.title3.weight(.heavy))
            Text(cls.section).font(.callout)
        }
        .foregroundStyle(Theme.textPrimary)
    }

    private var whenText: some View {
        Text("\(cls.weekdays.map(\.token).joined(separator: " ")) · \(FreeWindowSummary.classRange(cls.startMinutes, cls.endMinutes))")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(Theme.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The star next to the instructor follows the rating; no star color without a rating.
    private var tone: RatingTone? {
        guard case .found(let rating)? = lookup, rating.hasRatings else { return nil }
        return RatingStyle.tone(for: rating.overallRating)
    }
}

/// The blue band under the instructor with the numbers, or a short explanation when there are none.
private struct RatingBand: View {
    let lookup: ProfessorRatingLookup?

    var body: some View {
        Group {
            switch lookup {
            case nil:
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading rating…")
                }
            case .found(let rating) where rating.hasRatings:
                stats(rating)
            case .found, .notFound:
                Text("No RateMyProfessors rating found")
            case .unavailable:
                Text("Rating unavailable right now")
            }
        }
        .font(.subheadline)
        .foregroundStyle(Theme.navy)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.carolinaBlue, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// Always one horizontal row inside the band. The row never wraps; it caps the text size so
    /// it fits and shrinks slightly instead.
    @ViewBuilder
    private func stats(_ rating: ProfessorRating) -> some View {
        HStack(spacing: 12) {
            ratingPill(rating)
            stat(RatingStyle.decimalText(rating.difficulty), "Difficulty")
            stat(RatingStyle.percentText(rating.wouldTakeAgainPercent), "Take again")
            if RatingStyle.isLowCount(rating.numRatings) {
                lowCountStat(rating.numRatings)
            } else {
                stat("\(rating.numRatings)", "Ratings")
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Rated \(RatingStyle.decimalText(rating.overallRating)) out of 5, difficulty \(RatingStyle.decimalText(rating.difficulty)), "
            + "\(RatingStyle.percentText(rating.wouldTakeAgainPercent)) would take again, \(rating.numRatings) ratings"
            + (RatingStyle.isLowCount(rating.numRatings) ? ", low count" : ""))
    }

    private func ratingPill(_ rating: ProfessorRating) -> some View {
        Text(RatingStyle.ratingText(rating.overallRating))
            .font(.headline.weight(.heavy))
            .foregroundStyle(Color.white)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(pillColor(for: RatingStyle.tone(for: rating.overallRating)), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 0) {
            Text(value).font(.headline.weight(.bold))
            Text(label).font(.footnote)
        }
        .multilineTextAlignment(.center)
    }

    /// Fewer than 5 ratings: the count carries a warning symbol and the label says why.
    private func lowCountStat(_ count: Int) -> some View {
        VStack(spacing: 0) {
            Label("\(count)", systemImage: "exclamationmark.triangle.fill").font(.headline.weight(.bold))
            Text("Low count").font(.footnote.weight(.bold))
        }
        .multilineTextAlignment(.center)
    }
}

private func pillColor(for tone: RatingTone) -> Color {
    switch tone {
    case .good: Theme.ratingGood
    case .fair: Theme.ratingFair
    case .poor: Theme.ratingPoor
    }
}

private func color(for tone: RatingTone) -> Color {
    switch tone {
    case .good: Theme.success
    case .fair: Theme.caution
    case .poor: Theme.danger
    }
}

#Preview {
    let model = ScheduleViewModel()
    let services = AppServices.preview()
    return ClassesListView(viewModel: model, onImport: {}, onLoadDemo: {})
        .environment(services)
        .background(Theme.screenBackground)
        .task {
            await model.load(from: services.schedule)
            await model.loadRatings(from: services.schedule)
        }
}
