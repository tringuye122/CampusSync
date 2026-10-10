//
//  ScheduleWidget.swift
//  ScheduleWidget
//
//  Shows your current or next class (or free block) plus the top friend invite.
//  It reads only the JSON snapshot in the App Group: no SwiftData, no network.
//  The timeline is pre-built at class and invite boundaries (see
//  WidgetTimelineBuilder); the app calls reloadAllTimelines() after local writes.
//

import SwiftUI
import WidgetKit

// MARK: - Timeline

struct ScheduleEntry: TimelineEntry {
    let data: WidgetEntryData
    var date: Date { data.date }
}

struct ScheduleProvider: TimelineProvider {
    func placeholder(in context: Context) -> ScheduleEntry {
        ScheduleEntry(data: SampleWidgetData.entry)
    }

    func getSnapshot(in context: Context, completion: @escaping (ScheduleEntry) -> Void) {
        if context.isPreview {
            completion(ScheduleEntry(data: SampleWidgetData.entry))
        } else {
            completion(plan().entries.first.map(ScheduleEntry.init) ?? ScheduleEntry(data: SampleWidgetData.empty))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ScheduleEntry>) -> Void) {
        let plan = plan()
        completion(Timeline(entries: plan.entries.map(ScheduleEntry.init), policy: .after(plan.reloadAt)))
    }

    /// Reads the snapshot (empty state on any problem) and pre-builds entries.
    /// The offset in the snapshot is the demo time override, so the widget
    /// matches the app. `Date()` here only seeds the real-time start.
    private func plan() -> WidgetTimelinePlan {
        let snapshot = WidgetSnapshot.load()
        return WidgetTimelineBuilder.plan(snapshot: snapshot, realNow: AppClock.now(offset: 0))
    }
}

// MARK: - Widget

struct ScheduleWidget: Widget {
    let kind = "ScheduleWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ScheduleProvider()) { entry in
            ScheduleWidgetEntryView(data: entry.data)
                .containerBackground(Theme.screenBackground, for: .widget)
        }
        .configurationDisplayName("CampusSync")
        .description("Your next class or free time, plus the top plan from friends.")
        .supportedFamilies([
            .systemSmall, .systemMedium,
            .accessoryRectangular, .accessoryCircular, .accessoryInline,
        ])
    }
}

// MARK: - Views

struct ScheduleWidgetEntryView: View {
    let data: WidgetEntryData
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall:
            SmallView(data: data)
                .widgetURL(URL(string: "campussync://schedule"))
        case .systemMedium:
            MediumView(data: data)
        case .accessoryRectangular:
            RectangularView(data: data)
                .widgetURL(URL(string: "campussync://schedule"))
        case .accessoryCircular:
            CircularView(data: data)
                .widgetURL(URL(string: "campussync://schedule"))
        case .accessoryInline:
            InlineView(data: data)
                .widgetURL(URL(string: "campussync://schedule"))
        default:
            SmallView(data: data)
        }
    }
}

/// What the status block says, shared by the home screen sizes.
private struct StatusText {
    var tag: String
    var title: String
    var detail: String
    var symbol: String
    /// Real time the countdown runs to, with its label ("ends in", "starts in").
    var countdownTarget: Date?
    var countdownLabel: String

    init(_ data: WidgetEntryData) {
        switch data.status {
        case let .inClass(meeting, endsAt, _):
            tag = "NOW"
            title = meeting.courseCode
            detail = meeting.location
            symbol = "book.closed.fill"
            countdownTarget = data.real(endsAt)
            countdownLabel = "Ends in"
        case let .freeBeforeNext(next, startsAt):
            tag = "FREE"
            title = "Free until \(next.startMinutes.clockString)"
            detail = "\(next.courseCode) next"
            symbol = "clock.fill"
            countdownTarget = data.real(startsAt)
            countdownLabel = "Class in"
        case let .nextClass(next, _):
            tag = "NEXT"
            title = next.courseCode
            detail = "\(Self.weekdayName(next.weekday)) \(next.startMinutes.clockString)"
            symbol = "calendar"
            countdownTarget = nil
            countdownLabel = ""
        case .noClasses:
            tag = "CAMPUSSYNC"
            title = "No schedule"
            detail = "Open the app to load your classes"
            symbol = "calendar.badge.plus"
            countdownTarget = nil
            countdownLabel = ""
        }
    }

    static func weekdayName(_ weekday: Int) -> String {
        let symbols = Calendar.current.shortWeekdaySymbols
        return symbols.indices.contains(weekday - 1) ? symbols[weekday - 1] : ""
    }
}

private struct StatusBlock: View {
    let status: StatusText

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(status.tag, systemImage: status.symbol)
                .font(.caption.bold())
                .foregroundStyle(Theme.textPrimary)
            Text(status.title)
                .font(.title3.bold())
                .foregroundStyle(Theme.textPrimary)
                .minimumScaleFactor(0.7)
                .lineLimit(2)
            Text(status.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if let target = status.countdownTarget {
                HStack(spacing: 4) {
                    Text(status.countdownLabel)
                    Text(target, style: .relative)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
        }
    }
}

private struct SmallView: View {
    let data: WidgetEntryData

    var body: some View {
        StatusBlock(status: StatusText(data))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct MediumView: View {
    let data: WidgetEntryData

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Link(destination: URL(string: "campussync://schedule")!) {
                StatusBlock(status: StatusText(data))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }

            Link(destination: URL(string: "campussync://invites")!) {
                InviteBlock(invite: data.topInvite)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(10)
                    .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
    }
}

private struct InviteBlock: View {
    let invite: SnapshotInvite?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("TOP INVITE", systemImage: "paperplane.fill")
                .font(.caption.bold())
                .foregroundStyle(Theme.textPrimary)
            if let invite {
                Text(invite.title)
                    .font(.subheadline.bold())
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                Label(invite.landmarkName, systemImage: invite.landmarkSymbol)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(timeText(invite))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
            } else {
                Text("No plans yet")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func timeText(_ invite: SnapshotInvite) -> String {
        invite.startTime.formatted(.dateTime.hour().minute())
    }
}

private struct RectangularView: View {
    let data: WidgetEntryData

    var body: some View {
        let status = StatusText(data)
        VStack(alignment: .leading, spacing: 2) {
            Label(status.title, systemImage: status.symbol)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let target = status.countdownTarget {
                HStack(spacing: 4) {
                    Text(status.countdownLabel)
                    Text(target, style: .relative)
                }
                .font(.caption)
                .lineLimit(1)
            } else {
                Text(status.detail)
                    .font(.caption)
                    .lineLimit(1)
            }
            if let invite = data.topInvite {
                Label("\(invite.title) · \(invite.startTime.formatted(.dateTime.hour().minute()))",
                      systemImage: invite.landmarkSymbol)
                    .font(.caption2)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CircularView: View {
    let data: WidgetEntryData

    var body: some View {
        let status = StatusText(data)
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: status.symbol)
                    .font(.caption)
                Text(shortLabel)
                    .font(.caption2.bold())
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }
        }
    }

    /// Short text that fits a circle: the course number, or the time the next class starts.
    private var shortLabel: String {
        switch data.status {
        case let .inClass(meeting, _, _):
            return meeting.courseCode.split(separator: " ").last.map(String.init) ?? meeting.courseCode
        case let .freeBeforeNext(next, _):
            return next.startMinutes.clockString.replacingOccurrences(of: " ", with: "")
        case let .nextClass(next, _):
            return next.courseCode.split(separator: " ").last.map(String.init) ?? next.courseCode
        case .noClasses:
            return "--"
        }
    }
}

private struct InlineView: View {
    let data: WidgetEntryData

    var body: some View {
        switch data.status {
        case let .inClass(meeting, endsAt, _):
            Label("\(meeting.courseCode) until \(minutes(endsAt).clockString)", systemImage: "book.closed.fill")
        case let .freeBeforeNext(next, _):
            Label("Free until \(next.startMinutes.clockString)", systemImage: "clock.fill")
        case let .nextClass(next, _):
            Label("Next: \(next.courseCode) \(StatusText.weekdayName(next.weekday))", systemImage: "calendar")
        case .noClasses:
            Label("CampusSync", systemImage: "calendar.badge.plus")
        }
    }

    private func minutes(_ date: Date) -> Int {
        date.minutesSinceMidnight()
    }
}

// MARK: - Preview data

enum SampleWidgetData {
    static var entry: WidgetEntryData {
        let calendar = Calendar.current
        let tuesday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 13, hour: 12, minute: 30))!
        let meetings = [
            SnapshotMeeting(courseCode: "COMP 433", location: "Sitterson Hall SN014",
                            weekday: 3, startMinutes: 660, endMinutes: 735),
            SnapshotMeeting(courseCode: "COMP 577", location: "Sitterson Hall FB009",
                            weekday: 3, startMinutes: 930, endMinutes: 1005),
        ]
        let invite = SnapshotInvite(
            id: UUID(), title: "Study group", landmarkName: "Davis Library",
            landmarkSymbol: "books.vertical",
            startTime: tuesday.addingTimeInterval(45 * 60), expiresAt: tuesday.addingTimeInterval(165 * 60))
        let snapshot = WidgetSnapshot(
            version: WidgetSnapshot.currentVersion, generatedAt: tuesday, clockOffset: 0,
            meetings: meetings, invites: [invite])
        return WidgetTimelineBuilder.plan(snapshot: snapshot, realNow: tuesday).entries[0]
    }

    static var empty: WidgetEntryData {
        WidgetTimelineBuilder.plan(snapshot: .empty, realNow: entry.virtualNow).entries[0]
    }
}

#Preview(as: .systemSmall) {
    ScheduleWidget()
} timeline: {
    ScheduleEntry(data: SampleWidgetData.entry)
    ScheduleEntry(data: SampleWidgetData.empty)
}

#Preview(as: .systemMedium) {
    ScheduleWidget()
} timeline: {
    ScheduleEntry(data: SampleWidgetData.entry)
}

#Preview(as: .accessoryRectangular) {
    ScheduleWidget()
} timeline: {
    ScheduleEntry(data: SampleWidgetData.entry)
}

#Preview(as: .accessoryCircular) {
    ScheduleWidget()
} timeline: {
    ScheduleEntry(data: SampleWidgetData.entry)
}

#Preview(as: .accessoryInline) {
    ScheduleWidget()
} timeline: {
    ScheduleEntry(data: SampleWidgetData.entry)
}
