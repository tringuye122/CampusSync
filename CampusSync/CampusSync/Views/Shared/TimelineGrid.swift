//
//  TimelineGrid.swift
//  CampusSync
//
//  A vertical day timeline: hour labels and lines on the left, and a content area on the right where
//  callers place blocks by minute using `TimelineMetrics`. Covers the waking-hours window (8 AM to
//  10 PM), scrolls, and opens at 9 AM so the school day is in view. Used by Timetable and Friends.
//

import SwiftUI

struct TimelineMetrics {
    let startMinutes: Int
    let endMinutes: Int
    let hourHeight: CGFloat

    func y(_ minutes: Int) -> CGFloat { CGFloat(minutes - startMinutes) / 60 * hourHeight }
    func height(from start: Int, to end: Int) -> CGFloat { CGFloat(end - start) / 60 * hourHeight }
    var totalHeight: CGFloat { height(from: startMinutes, to: endMinutes) }
}

struct TimelineGrid<Content: View>: View {
    var startMinutes = FreeSlotSettings.standard.dayStartMinutes
    var endMinutes = FreeSlotSettings.standard.dayEndMinutes
    var hourHeight: CGFloat = 64
    /// Minute to scroll to when the timeline appears.
    var initialScrollMinutes = 9 * 60
    /// Show a "now" marker at this minute (nil to hide it).
    var nowMinutes: Int?
    /// Optional titles for equal-width columns ("You", "Maya"), pinned above the scrolling hours.
    var columnTitles: [String] = []
    @ViewBuilder var content: (TimelineMetrics) -> Content

    private let axisWidth: CGFloat = 52

    var body: some View {
        let metrics = TimelineMetrics(startMinutes: startMinutes, endMinutes: endMinutes, hourHeight: hourHeight)
        VStack(spacing: 0) {
            if !columnTitles.isEmpty { titleRow }
        ScrollViewReader { proxy in
            ScrollView {
                ZStack(alignment: .topLeading) {
                    // Hour lines and labels, with an invisible anchor per hour to scroll to.
                    ForEach(Array(stride(from: startMinutes, through: endMinutes, by: 60)), id: \.self) { minute in
                        hourRow(minute, metrics: metrics)
                    }
                    content(metrics)
                        .padding(.leading, axisWidth)
                        .frame(height: metrics.totalHeight, alignment: .topLeading)
                    if let nowMinutes, (startMinutes...endMinutes).contains(nowMinutes) {
                        nowMarker.offset(y: metrics.y(nowMinutes) - 5)
                    }
                }
                .frame(height: metrics.totalHeight + 24, alignment: .topLeading)
                .padding(.vertical, 12)
                .padding(.horizontal, 12)
            }
            .onAppear { proxy.scrollTo("minute-\(initialScrollMinutes)", anchor: .top) }
        }
        }
        .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var titleRow: some View {
        HStack(spacing: 8) {
            ForEach(columnTitles, id: \.self) { title in
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .lineLimit(1)
            }
        }
        .padding(.leading, axisWidth + 12)
        .padding(.trailing, 12)
        .padding(.top, 14)
        .padding(.bottom, 4)
    }

    private func hourRow(_ minute: Int, metrics: TimelineMetrics) -> some View {
        HStack(alignment: .center, spacing: 6) {
            Text(label(for: minute))
                .font(.footnote)
                .foregroundStyle(Theme.textPrimary.opacity(0.8))
                .frame(width: axisWidth - 6, alignment: .leading)
            Rectangle().fill(Theme.hairline.opacity(0.6)).frame(height: 1)
        }
        .frame(height: 16)
        .offset(y: metrics.y(minute) - 8)
        .id("minute-\(minute)")
        .accessibilityHidden(true)
    }

    private var nowMarker: some View {
        HStack(spacing: 0) {
            Circle().fill(Theme.danger).frame(width: 10, height: 10)
            Rectangle().fill(Theme.danger).frame(height: 2)
        }
        .padding(.leading, axisWidth - 5)
        .accessibilityHidden(true)
    }

    private func label(for minutes: Int) -> String {
        let hour = (minutes / 60) % 24
        let h12 = hour % 12 == 0 ? 12 : hour % 12
        return "\(h12) \(hour < 12 ? "AM" : "PM")"
    }
}
