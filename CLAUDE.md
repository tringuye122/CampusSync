# CampusSync

Native iOS app for UNC Chapel Hill students, built for HackNC in a 24 to 48 hour window by a two-person team. It shows when you and your friends are free, what is happening on campus, and surfaces it all in a widget. The demo is a recorded run on a physical iPhone with Wi-Fi, online, on real Firebase data.

The goal is a live, scalable app, not a mocked demo: real accounts, a real friend graph, and data that syncs between phones. Seed data is a development, preview, test and fallback aid, not the product.

The full spec is in `docs/CampusSync_Spec_Doc.md` and has been updated for the Firebase backend. If this file and the spec disagree, ask before choosing.

## Stack

- Swift 5.9+, iOS 17+, SwiftUI, SwiftData, WidgetKit
- MVVM: Views -> ViewModels -> Repository protocols -> SwiftData
- App Group shared container for app-to-widget data
- Firebase Auth + Firestore are the live backend (accounts, friend graph, shared schedules, invites, clubs). Use the Firebase iOS SDK via Swift Package Manager, with only `FirebaseAuth` and `FirebaseFirestore`. Add the dependency during the Firebase phase, not before.
- Sign-in is email and password restricted to `@unc.edu` with email verification. Friends are added by handle search with request and accept.
- The local SwiftData repositories and `SampleData.swift` stay for previews, tests and offline fallback.

## Hard rules

1. **Network is allowed, but must fail safe.** The demo and the app may use the network. Every network feature must degrade gracefully: cache what it fetched, show a clear empty or offline state, and never crash or block a screen. `SampleData.swift` seed data is the dev/demo-mode and fallback data source, and the app must still launch and be usable with no connection.
2. **Repository protocols.** Views and ViewModels never touch SwiftData or Firestore directly. Use `UserRepository`, `ScheduleRepository`, `InviteRepository`, `ClubRepository` (and friend access). Firestore implementations are the real ones; the local implementations remain for previews, tests and fallback.
3. **One clock.** Every "now" goes through a single injectable `AppClock`. Never call `Date()` in views, view models, or the widget provider. The demo needs a time override ("as if it is Tuesday 12:30 PM").
4. **Widget reads only a JSON snapshot.** The app writes a small `Codable` `WidgetSnapshot` (with a `version` field) to the App Group container, then calls `WidgetCenter.shared.reloadAllTimelines()`, including whenever a Firestore listener delivers a change. The widget never opens the SwiftData store, never links Firebase, and never uses the network. On a bad or missing snapshot, show an empty state. Without push notifications, friends' changes reach the widget after the app next runs or foregrounds.
5. **Widget timelines are pre-built.** Create entries at known boundaries (class start, class end, invite expiry) and set a reload policy for the next boundary. Do not assume continuous updates.
6. **Widget families:** `systemSmall`, `systemMedium`, plus `accessoryRectangular`, `accessoryCircular`, `accessoryInline` for the Lock Screen.
7. **Expiry is filtered at read time.** An invite is expired when `now > expiresAt`. Store `expiresAt` as an absolute `Date`.
8. **No Apple Pay, no PassKit.** "Pay Dues" is a one-tap button that records a membership in Firestore and shows a "Verified Member" badge. No real payment.
9. **"Nearby" means tagged to a campus landmark.** No Core Location.
10. **Privacy.** Never store, log, or display the student ID from the ConnectCarolina PDF. Parse only the term and courses. Never commit real schedule PDFs. Do not commit `GoogleService-Info.plist` or any service account key. A student's shared schedule in Firestore holds meeting times only (weekday, start and end, building, course code), never course titles, instructors, name, or ID, and is readable only by accepted friends.
11. **Seed data is fictional,** except the demo user's own class schedule, which uses the real instructors from the sample ConnectCarolina PDF. **Professor ratings are never invented:** they come from RateMyProfessors (cached), are credited to RateMyProfessors on screen, and fall back to "no rating" when unavailable. RateMyProfessors has no official API, so keep that lookup isolated behind `ProfessorRatingProvider`.

12. **Firestore security.** Security rules live in `firebase/firestore.rules`, are tested in the Firebase emulator, and must be written before any real write is enabled. Rules enforce verified `@unc.edu` accounts, host-only invite creation, friends-only schedule reads, and unique handles. Never trust the client alone.

## Product rules

- **Friend Invites** go only to friends the user has added; the poster picks who gets each plan. The Swift type may still be named `OpenInvite`/`OpenInviteCardView`; keep names consistent with the code that exists.
- `OpenInvite` needs `recipientIDs` (who was invited) and the user needs a `friendIDs` list. The friend graph comes from Firestore (friend requests and accepted friendships); seed data is used only for previews and tests.
- **Club events are public.** Users who subscribe or join a club are notified.
- The first-listed instructor on a class is the professor shown in the rating sheet (rating fetched from RateMyProfessors). Label the field "Instructor".
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
  Firebase/            Firestore repository implementations, AuthService
  Support/             Theme.swift, AppClock.swift, AppGroupManager.swift, SampleData.swift
ScheduleWidget/        widget extension (ScheduleWidget.swift)
firebase/              firestore.rules, firestore.indexes.json, seeding script, emulator tests
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
6. PDF import: parser, review screen, demo fallback, RateMyProfessors ratings
7. Firebase foundation: Firebase project and SDK, Auth sign up and sign in (`@unc.edu`, email verification), user profile and handles, security rules with emulator tests
8. Sync and friends: friend search, request and accept; Firestore repositories for schedule, invites and clubs; listeners feeding the snapshot writer; seeding script for clubs and demo data
9. Friend overlap: `OverlapEngine`, `FriendScheduleOverlayView` over real friends' shared schedules
10. Clubs: feed over Firestore, access badges, Join and Pay Dues memberships
11. Polish: dark mode, empty states, dev menu (time override, reset demo data), demo recording
12. Stretch: `.ics` import, push notifications (FCM), report and block, App Check

Cut order if time runs short: Clubs polish, overlap polish, PDF import (use the demo schedule), widget families beyond small and medium. Never cut the widget, Friend Invites, or real accounts and sync.

## Working agreements

- `Models.swift` and `WidgetSnapshot` are frozen after phase 1 except for additive fields. Announce any change.
- Prefer small, scoped changes. Do not refactor files outside the current phase.
- Put each feature in its own files to avoid `.xcodeproj` merge conflicts. Only one person edits targets and capabilities.
- Write clear comments on non-obvious logic (parser regexes, timeline boundaries, overlap math).
- Add SwiftUI previews for every view, using seed data.
- Test widgets and the Lock Screen on a physical iPhone early. The simulator is not reliable for them.
- Do not run destructive git commands or delete files without asking.
- Do not write to, delete from, or change rules on the real Firebase project without asking. Use the emulator for development and tests.
