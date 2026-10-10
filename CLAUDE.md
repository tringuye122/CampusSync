# CampusSync

Native iOS app for UNC Chapel Hill students, built for HackNC in a 24 to 48 hour window by a two-person team. It shows when you and your friends are free, what is happening on campus, and surfaces it all in a widget. The demo is a recorded run on a physical iPhone with Wi-Fi.

The full spec is in `docs/CampusSync_Spec_Doc.md`. If this file and the spec disagree, ask before choosing.

## Stack

- Swift 5.9+, iOS 17+, SwiftUI, SwiftData, WidgetKit
- MVVM: Views -> ViewModels -> Repository protocols -> SwiftData
- App Group shared container for app-to-widget data
- Firebase Auth + Firestore are STRETCH. Do not add Firebase dependencies unless asked.

## Hard rules

1. **Seed data is the default.** The app must run fully offline from `SampleData.swift`. Nothing in the demo path may depend on the network.
2. **Repository protocols.** Views and ViewModels never touch SwiftData or Firestore directly. Use `InviteRepository`, `ClubRepository`, `ScheduleRepository`. Mock/local implementations first.
3. **One clock.** Every "now" goes through a single injectable `AppClock`. Never call `Date()` in views, view models, or the widget provider. The demo needs a time override ("as if it is Tuesday 12:30 PM").
4. **Widget reads only a JSON snapshot.** The app writes a small `Codable` `WidgetSnapshot` (with a `version` field) to the App Group container, then calls `WidgetCenter.shared.reloadAllTimelines()`. The widget never opens the SwiftData store and never uses the network. On a bad or missing snapshot, show an empty state.
5. **Widget timelines are pre-built.** Create entries at known boundaries (class start, class end, invite expiry) and set a reload policy for the next boundary. Do not assume continuous updates.
6. **Widget families:** `systemSmall`, `systemMedium`, plus `accessoryRectangular`, `accessoryCircular`, `accessoryInline` for the Lock Screen.
7. **Expiry is filtered at read time.** An invite is expired when `now > expiresAt`. Store `expiresAt` as an absolute `Date`.
8. **No Apple Pay, no PassKit.** "Pay Dues" is a one-tap button that flips local state and shows a "Verified Member" badge.
9. **"Nearby" means tagged to a campus landmark.** No Core Location.
10. **Privacy.** Never store, log, or display the student ID from the ConnectCarolina PDF. Parse only the term and courses. Never commit real schedule PDFs. Do not commit `GoogleService-Info.plist`.
11. **Fictional data only** in seed data, except the demo user's own class schedule shape (see spec section 7). Professor ratings are invented and shown with a visible "Demo data" footer.

## Product rules

- **Friend Invites** go only to friends the user has added; the poster picks who gets each plan. The Swift type may still be named `OpenInvite`/`OpenInviteCardView`; keep names consistent with the code that exists.
- `OpenInvite` needs `recipientIDs` (who was invited) and the user needs a `friendIDs` list. The friend graph comes from seed data in the MVP.
- **Club events are public.** Users who subscribe or join a club are notified.
- The first-listed instructor on a class is the professor shown in the rating sheet. Label the field "Instructor".
- Free slots: minimum gap 30 minutes, waking hours 8 AM to 10 PM, a configurable walking buffer between buildings. Confirm these values with the team before building the overlap view.

## Schedule import

ConnectCarolina class-schedule PDF is the primary import. `.ics` is a stretch importer.

- `ScheduleImporter` protocol, with `ConnectCarolinaPDFParser` (primary) and `ICSParser` (stretch).
- Extract text with PDFKit from ALL pages and concatenate before parsing (course cards split across page breaks). Fall back to Vision OCR only if the extracted text is empty.
- Drop page chrome (timestamp header, footer URL, `1/2` counters).
- Split into course blocks on the course-code heading (`^[A-Z]{3,4}\s\d{3}[A-Z]?$`), then extract each label independently with a regex that captures up to the next known label. Do not rely on line order.
- Days are two-letter tokens (`Mo Tu We Th Fr`). Times are 12-hour (`1:25 PM`), stored as minutes after midnight. The Dates field has no year; take it from the term in the header. Room strings are truncated (`Sitterson Hall (inc-Rm FB009`); strip the stray fragment. Instructors can wrap across lines.
- Always show a review screen before saving, and keep a "Load demo schedule" button as the fallback.
- The first task for this module: print the raw PDFKit string for the sample PDF and write the regexes against that real output.

## Design system

- Carolina Blue `#7BAFD4` (fills, buttons, selected tab). Navy `#13294B` for text and dark surfaces. Use asset-catalog colors so dark mode works.
- Cards: 20 pt corner radius, 16 pt padding, minimum 44 pt tap targets. Shared `CardStyle` modifier in `Theme.swift`.
- Category pills (Food, Study, Fitness, Social) always pair color with an SF Symbol. Support Dynamic Type and add VoiceOver labels to timetable blocks.
- Four tabs: Home, Schedule (My Schedule / Friend Overlap), Friend Invites, Clubs.

## Project layout

```
CampusSync/            app target
  Models/              Models.swift, WidgetSnapshot.swift
  Repositories/        protocols + mock implementations
  ViewModels/
  Views/               Home, Schedule, Invites, Clubs, shared components
  Import/              ScheduleImporter, ConnectCarolinaPDFParser, ICSParser
  Support/             Theme.swift, AppClock.swift, AppGroupManager.swift, SampleData.swift
ScheduleWidget/        widget extension (ScheduleWidget.swift)
docs/CampusSync_Spec_Doc.md   master spec
```

## Build order

Work one phase at a time and stop for review after each.

0. Setup: targets, App Group, entitlements, `AppGroupManager`
1. Foundation: `Models.swift`, `Theme.swift`, `AppClock`, `SampleData.swift`, repository protocols
2. Shell: `MainTabView`, `HomeDashboardView` with placeholder screens
3. Schedule: timetable grid, free-slot calculation, `ProfessorRatingSheet`
4. Friend Invites: feed, `OpenInviteCardView`, compose sheet, RSVP, expiry
5. Widget: snapshot writer, `TimelineProvider`, all families
6. PDF import: parser, review screen, demo fallback
7. Friend overlap: `OverlapEngine`, `FriendScheduleOverlayView`
8. Clubs: feed, access badges, Pay Dues state
9. Polish: dark mode, empty states, dev menu (time override, reset to seed), demo recording
10. Stretch: `.ics` import, Firestore repositories, Auth

Cut order if time runs short: Clubs polish, overlap polish, PDF import (use the demo schedule), widget families beyond small and medium. Never cut the widget or Friend Invites.

## Working agreements

- `Models.swift` and `WidgetSnapshot` are frozen after phase 1 except for additive fields. Announce any change.
- Prefer small, scoped changes. Do not refactor files outside the current phase.
- Put each feature in its own files to avoid `.xcodeproj` merge conflicts. Only one person edits targets and capabilities.
- Write clear comments on non-obvious logic (parser regexes, timeline boundaries, overlap math).
- Add SwiftUI previews for every view, using seed data.
- Test widgets and the Lock Screen on a physical iPhone early. The simulator is not reliable for them.
- Do not run destructive git commands or delete files without asking.
