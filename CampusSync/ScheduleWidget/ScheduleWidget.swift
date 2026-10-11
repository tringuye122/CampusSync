//
//  ScheduleWidget.swift
//  ScheduleWidget
//
//  Home Screen: small (up next), medium (up next plus a friend who is free) and large
//  (who is free). Lock Screen: rectangular, circular and inline keep the class status and the
//  top invite. It reads only the JSON snapshot in the App Group: no SwiftData, no network.
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
        }
        .configurationDisplayName("CampusSync")
        .description("Your next class, and which friends are free right now.")
        .supportedFamilies([
            .systemSmall, .systemMedium, .systemLarge,
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
                .widgetBackground(Theme.carolinaBlue)
                .widgetURL(URL(string: "campussync://home"))
        case .systemMedium:
            MediumView(data: data)
                .widgetBackground(Theme.carolinaBlue)
                .widgetURL(URL(string: "campussync://home"))
        case .systemLarge:
            LargeView(data: data)
                .widgetBackground(Theme.cardBackground)
                .widgetURL(URL(string: "campussync://home"))
        case .accessoryRectangular:
            RectangularView(data: data)
                .widgetBackground(Theme.screenBackground)
                .widgetURL(URL(string: "campussync://home"))
        case .accessoryCircular:
            CircularView(data: data)
                .widgetBackground(Theme.screenBackground)
                .widgetURL(URL(string: "campussync://home"))
        case .accessoryInline:
            InlineView(data: data)
                .widgetBackground(Theme.screenBackground)
                .widgetURL(URL(string: "campussync://home"))
        default:
            SmallView(data: data)
                .widgetBackground(Theme.carolinaBlue)
        }
    }
}

private extension View {
    func widgetBackground(_ color: Color) -> some View {
        containerBackground(color, for: .widget)
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

// MARK: Home Screen layouts

/// The "up next" text shared by small and medium.
private struct NextUp {
    var tag: String
    var title: String
    var shortTime: String
    var timeRange: String
    var place: String

    init(_ data: WidgetEntryData) {
        switch data.status {
        case let .inClass(meeting, endsAt, _):
            tag = "NOW"
            title = meeting.courseCode
            shortTime = "Until \(Self.minutes(endsAt).clockString)"
            timeRange = WidgetFriendStatusEngine.rangeText(meeting.startMinutes, meeting.endMinutes, separator: " – ")
            place = meeting.location
        case let .freeBeforeNext(next, _):
            tag = "UP NEXT"
            title = next.courseCode
            shortTime = next.startMinutes.clockString
            timeRange = WidgetFriendStatusEngine.rangeText(next.startMinutes, next.endMinutes, separator: " – ")
            place = next.location
        case let .nextClass(next, _):
            let day = StatusText.weekdayName(next.weekday)
            tag = "UP NEXT"
            title = next.courseCode
            shortTime = "\(day) \(next.startMinutes.clockString)"
            timeRange = "\(day) \(WidgetFriendStatusEngine.rangeText(next.startMinutes, next.endMinutes, separator: " – "))"
            place = next.location
        case .noClasses:
            tag = "CAMPUSSYNC"
            title = "No schedule"
            shortTime = "Open the app"
            timeRange = "Open the app to load your classes"
            place = ""
        }
    }

    private static func minutes(_ date: Date) -> Int { date.minutesSinceMidnight() }
}

/// Initials in a circle: "JN" for two words, the first two letters for one.
private func initials(_ name: String) -> String {
    let words = name.split(whereSeparator: \.isWhitespace)
    switch words.count {
    case 0: return "?"
    case 1: return String(words[0].prefix(2)).uppercased()
    default: return (String(words[0].prefix(1)) + String(words[words.count - 1].prefix(1))).uppercased()
    }
}

/// The student's avatar and @handle at the top of the small and medium widgets.
private struct UserHeader: View {
    let data: WidgetEntryData

    var body: some View {
        HStack(spacing: 8) {
            Text(initials(data.userName ?? data.userHandle ?? ""))
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.navy)
                .frame(width: 30, height: 30)
                .background(Color.white.opacity(0.92), in: Circle())
            Text(data.userHandle.map { "@\($0)" } ?? "CampusSync")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }
}

private struct SmallView: View {
    let data: WidgetEntryData

    var body: some View {
        let next = NextUp(data)
        VStack(alignment: .leading, spacing: 0) {
            UserHeader(data: data)
            Spacer(minLength: 6)
            Text(next.tag)
                .font(.caption.weight(.heavy))
                .tracking(2)
                .foregroundStyle(Theme.navy)
            Text(next.title)
                .font(.system(size: 30, weight: .heavy))
                .foregroundStyle(Color.white)
                .lineLimit(2)
                .minimumScaleFactor(0.6)
            Text(next.shortTime)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct MediumView: View {
    let data: WidgetEntryData

    var body: some View {
        let next = NextUp(data)
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                UserHeader(data: data)
                Spacer(minLength: 6)
                Text(next.tag)
                    .font(.caption.weight(.heavy))
                    .tracking(2)
                    .foregroundStyle(Theme.navy)
                Text(next.title)
                    .font(.system(size: 28, weight: .heavy))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(next.timeRange)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if !next.place.isEmpty {
                    Text(next.place)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)

            Rectangle()
                .fill(Theme.navy.opacity(0.35))
                .frame(width: 1)
                .padding(.vertical, 4)
                .padding(.horizontal, 14)

            FriendFreePanel(friends: data.friends)
                .frame(width: 128)
        }
    }
}

/// The right side of the medium widget: the friend who has been free the longest, or why nobody is.
private struct FriendFreePanel: View {
    let friends: [WidgetFriendRow]

    var body: some View {
        VStack(spacing: 4) {
            if let free = friends.first(where: \.isFree) {
                circle(initials: String(free.name.prefix(1)))
                Text("\(firstName(free.name)) is Free")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(untilText(free))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.navy)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else {
                circle(symbol: "person.2.fill")
                Text(friends.isEmpty ? "No friends yet" : "No one is free")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(Color.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(friends.isEmpty ? "Add some in the app" : "Everyone is in class")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.navy)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func circle(initials: String? = nil, symbol: String? = nil) -> some View {
        Group {
            if let initials {
                Text(initials).font(.system(size: 24, weight: .bold, design: .rounded))
            } else if let symbol {
                Image(systemName: symbol).font(.title3)
            }
        }
        .foregroundStyle(Theme.navy)
        .frame(width: 58, height: 58)
        .background(Color.white.opacity(0.92), in: Circle())
        .overlay(Circle().strokeBorder(Color.white, lineWidth: 2))
    }

    private func firstName(_ name: String) -> String {
        name.split(separator: " ").first.map(String.init) ?? name
    }

    private func untilText(_ row: WidgetFriendRow) -> String {
        guard case .free(let until) = row.state, let until else { return "Rest of today" }
        return "Until \(until.clockString)"
    }
}

private struct LargeView: View {
    let data: WidgetEntryData
    private static let maxRows = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image("UNCSeal")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 30)
                    .accessibilityHidden(true)
                Text("Friends' Status")
                    .font(.title3.weight(.heavy))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 0)
            }
            if data.friends.isEmpty {
                Spacer()
                Text("Add friends in the app and share schedules to see who is free.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .multilineTextAlignment(.center)
                Spacer()
            } else {
                // Rows share the card's height evenly.
                VStack(spacing: 0) {
                    ForEach(data.friends.prefix(Self.maxRows)) { row in
                        Spacer(minLength: 6)
                        FriendRowView(row: row)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

private struct FriendRowView: View {
    let row: WidgetFriendRow

    var body: some View {
        HStack(spacing: 10) {
            Text(String(row.name.prefix(1)))
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.navy)
                .frame(width: 44, height: 44)
                .background(Theme.carolinaBlue, in: Circle())
            Text(row.name.split(separator: " ").first.map(String.init) ?? row.name)
                .font(.headline.weight(.heavy))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 66, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                FreeBar(row: row)
                Text(row.rangeText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            Text(row.isFree ? "Free" : "In Class")
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(row.isFree ? Theme.navy : Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 84, height: 40)
                .background(row.isFree ? Theme.carolinaBlue : Theme.pillBackground, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        switch row.state {
        case .free(let until?): "\(row.name) is free until \(until.clockString)"
        case .free(nil): "\(row.name) is free for the rest of today"
        case .inClass(let until): "\(row.name) is in class until \(until.clockString)"
        }
    }
}

/// Light blue where the friend is free, navy where they are in class, across the row's range.
private struct FreeBar: View {
    let row: WidgetFriendRow

    var body: some View {
        GeometryReader { proxy in
            let span = CGFloat(max(1, row.rangeEnd - row.rangeStart))
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.carolinaBlue)
                // Class blocks are navy; the hairline keeps the bar's ends visible on a dark card.
                ForEach(Array(row.classBlocks.enumerated()), id: \.offset) { _, block in
                    Rectangle()
                        .fill(Theme.navy)
                        .frame(width: max(3, CGFloat(block.endMinutes - block.startMinutes) / span * proxy.size.width))
                        .offset(x: CGFloat(block.startMinutes - row.rangeStart) / span * proxy.size.width)
                }
            }
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Theme.hairline, lineWidth: 1))
        }
        .frame(height: 14)
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
            id: UUID().uuidString, title: "Study group", landmarkName: "Davis Library",
            landmarkSymbol: "books.vertical",
            startTime: tuesday.addingTimeInterval(45 * 60), expiresAt: tuesday.addingTimeInterval(165 * 60))
        func block(_ start: Int, _ end: Int) -> SnapshotBlock { SnapshotBlock(weekday: 3, startMinutes: start, endMinutes: end) }
        let friends = [
            SnapshotFriend(id: "a", name: "Alex", blocks: [block(17 * 60, 18 * 60)]),
            SnapshotFriend(id: "j", name: "Jordan", blocks: [block(12 * 60, 13 * 60 + 45)]),
            SnapshotFriend(id: "m", name: "Maya", blocks: [block(13 * 60, 14 * 60), block(15 * 60 + 30, 16 * 60 + 30)]),
            SnapshotFriend(id: "d", name: "Dee", blocks: [block(9 * 60, 10 * 60)]),
        ]
        let snapshot = WidgetSnapshot(
            version: WidgetSnapshot.currentVersion, generatedAt: tuesday, clockOffset: 0,
            meetings: meetings, invites: [invite],
            userHandle: "Justin", userName: "Justin Nguyen", friends: friends)
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

#Preview(as: .systemLarge) {
    ScheduleWidget()
} timeline: {
    ScheduleEntry(data: SampleWidgetData.entry)
    ScheduleEntry(data: SampleWidgetData.empty)
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
