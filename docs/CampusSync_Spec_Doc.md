# CampusSync: HackNC Master Spec

Oct 10, 2026 · @tri

## 1. Overview

CampusSync (working name, lock it before creating bundle IDs) is a native iOS app that tells UNC Chapel Hill students when they and their friends are free, and what is happening on campus right now. It targets three frictions: schedule gaps nobody notices, club events nobody finds, and spontaneous plans that never get made.

**The hook:** a Home Screen and Lock Screen widget shows your next class or free block plus the top friend invite, without opening the app. It reads from a shared on-device container, so it never touches the network.

**Four pillars**

- **Schedule engine.** Upload your ConnectCarolina class schedule PDF, parse it on-device into `ClassSchedule` models, and see a weekly timetable with class blocks and free gaps. Tapping a class opens a professor rating sheet (mock data).
- **Friend overlap.** Compare two weekly schedules and highlight mutual free windows (`FreeSlot`).
- **Friend Invites.** Time-boxed plans you send only to friends you have added in the app, tied to campus landmarks (The Pit, Chase Dining Hall, Davis Library) with category tags (Food, Study, Fitness, Social), RSVP, and auto-expiration.
- **Clubs Hub.** A feed of GBMs and events with access badges (Public, Members Only, Dues Required) and a one-tap Join Club / Pay Dues action.

**Stack:** Swift 5.9+, iOS 17+, SwiftUI, SwiftData, MVVM, WidgetKit, App Groups. Firebase Auth and Firestore are an optional layer behind a repository protocol, added only if time allows.

## 2. Scope and locked decisions

The demo must run fully offline from seed data; everything networked is optional. These decisions replace the contradictions in the earlier drafts.

**Decisions**

1. **Mock data first, Firebase only if time permits.** All data access goes through repository protocols (`InviteRepository`, `ClubRepository`, `ScheduleRepository`). The mock implementation ships first; a Firestore implementation swaps in later.
2. **Schedule import is a ConnectCarolina PDF upload.** The student prints or saves their class schedule from ConnectCarolina as a PDF and imports it. `.ics` becomes a secondary importer, not the headline.
3. **No Apple Pay or PassKit.** Dues are a one-tap "Pay Dues" button that flips local state and shows a "Verified Member" badge.
4. **"Nearby" means tagged to a campus landmark.** No Core Location.
5. **Widget refresh is local.** The app calls `WidgetCenter.shared.reloadAllTimelines()` on local writes and on foreground. No push notifications.
6. **One shared container strategy:** a small Codable JSON snapshot in the App Group, not a shared SwiftData store.

**Scope table**

| Feature | Tier | MVP approach |
| --- | --- | --- |
| PDF schedule import + timetable | MVP | PDFKit text extraction, regex parser, demo schedule fallback |
| Friend overlap | MVP | Demo friend from seed data; overlap computed locally |
| Friend Invites feed, RSVP, expiry | MVP | Local store, expired invites filtered at read time |
| Widget (small, medium, Lock Screen) | MVP | JSON snapshot in App Group, timeline entries at known boundaries |
| Professor rating sheet | MVP | Hardcoded mock scores in seed data |
| Clubs feed + access badges | MVP | Seed data, one-tap Join / Pay Dues |
| Seed data | MVP | Real sample schedule shape plus fictional friends, invites, clubs |
| `.ics` import | Stretch | Simple parser, no recurrence support at first |
| Firebase Auth + Firestore | Stretch | Behind repository protocols |
| Real friend requests | Stretch | Needs Firestore rules |
| PassKit membership pass | Deferred | Static badge instead |
| Apple Pay sheet | Deferred | One-tap button instead |
| Club treasury visualizer | Deferred | Static descriptions |
| Live RateMyProfessor data | Deferred | Mock scores only |

## 3. Architecture

The app and the widget share data through one JSON snapshot in the App Group container, and everything else stays inside the main app.

&#91;embedded content: architecture layers · app, widget, shared snapshot\]

The app writes the snapshot after any local change and asks WidgetKit to reload; the widget's `TimelineProvider` only ever reads that file.

**Layer rules**

- Views talk only to ViewModels, and ViewModels talk only to repository protocols and the logic layer, never to SwiftData directly.
- The widget target shares only `WidgetSnapshot` and the theme with the app. It does not open the SwiftData store.
- The mock repositories ship first; Firebase repositories implement the same protocols later.

**Data flows**

1. **Schedule import.** Student picks the ConnectCarolina PDF, PDFKit extracts the text, `ConnectCarolinaPDFParser` produces `ClassSchedule` models, the student confirms them on a review screen, they save to SwiftData, and the app rewrites the snapshot and reloads the widget.
2. **Schedule overlap.** Student picks a friend, the app loads that friend's classes (seed data now, Firestore later), `OverlapEngine` intersects both free-slot lists on the device, and the overlay view renders the mutual windows.
3. **Friend invite.** Student posts an invite, the repository saves it, the invites feed refreshes, the app writes the new top invite into the snapshot, and `reloadAllTimelines()` updates the widget. When Firestore is added, its listener triggers the same path.

## 4. Schedule import (ConnectCarolina PDF)

The sample PDF is a labeled, repeating card layout, which makes it far easier to parse than a Canvas `.ics` feed. Replace `iCalParser.swift` with a `ScheduleImporter` protocol and two implementations: `ConnectCarolinaPDFParser` (primary) and `ICSParser` (stretch).

**What the sample file contains**

Each course is a card with the same labels: course code as a heading, then Section, Description, Wait List Position, Units, Instructor, Days, Start, End, Room, Dates. The header carries name, term ("2026 Fall"), and a retrieval timestamp. The sample has four courses across two pages: COMP 523, COMP 433, LING 460, and COMP 577.

**Field mapping**

| PDF label | Model field | Parsing note |
| --- | --- | --- |
| Course heading (`COMP 523`) | `courseCode` | Regex `^[A-Z]{3,4}\s\d{3}[A-Z]?$` starts a new course block |
| Description | `title` | Uppercase and abbreviated ("SOFTWARE ENGRNG LAB"); title-case it, keep a prettier name override table for the demo |
| Section, Units | `section`, `units` | Plain values |
| Instructor | `instructors: [String]` | Comma-separated, may wrap lines ("Tarik Reza\\nToha"); rejoin lines before splitting. First name is the primary professor |
| Days (`MoWe`, `TuTh`) | `weekdays: [Weekday]` | Split into two-letter tokens: Mo, Tu, We, Th, Fr |
| Start / End (`1:25 PM`) | `startMinutes`, `endMinutes` | 12-hour clock, store as minutes after midnight |
| Room | `building`, `room` | Truncated by ConnectCarolina ("Sitterson Hall (inc-Rm FB009"); strip the stray `(inc-Rm` fragment |
| Dates (`08/17 - 12/11`) | `startDate`, `endDate` | No year in the PDF; take it from the header term |
| Wait List Position | ignored | Always "-" in the sample |

**Pipeline**

1. Student picks the PDF with `fileImporter` (`UTType.pdf`).
2. PDFKit's `PDFDocument.string` extracts text from all pages. If the result is empty, the PDF is scanned: fall back to Vision `VNRecognizeTextRequest`.
3. Drop page chrome: lines matching the timestamp header, the `pa.cc.unc.edu` footer URL, and `1/2` page counters.
4. Read the term year from the header, then split the remaining text into course blocks on the course-code heading.
5. Inside each block, extract each label independently with a regex that captures up to the next known label. Do not assume line order, because two-column PDFs often extract left column then right column.
6. Show a confirmation screen listing parsed classes so the student can fix errors before saving.
7. Save to SwiftData and write the widget snapshot.

```swift
enum Weekday: Int, CaseIterable { case mon = 2, tue, wed, thu, fri }

func parseDays(_ raw: String) -> [Weekday] {
    let map: [String: Weekday] = ["Mo": .mon, "Tu": .tue, "We": .wed, "Th": .thu, "Fr": .fri]
    let chars = Array(raw)
    return stride(from: 0, to: chars.count - 1, by: 2).compactMap {
        map[String(chars[$0...$0 + 1])]
    }
}
```

**Risks specific to this format**

- The page break splits the COMP 577 card onto page 2, so parse the concatenated text of all pages, never page by page.
- The header contains the student's name and university ID. Parse only the term; never store or log the ID, and keep real PDFs out of the git repo.
- Co-instructors and TAs appear in the Instructor field (one name, Louie Lu, appears on three courses). Decision: the first-listed instructor is the professor shown in the rating sheet; label the field "Instructor" in the UI.
- Text extraction behavior depends on how the PDF was generated. Test PDFKit on this exact file in the first hour, before building anything on top of it.
- Always keep a "Load demo schedule" button so a failed import never blocks the demo.

## 5. Data models

SwiftData `@Model` classes hold the app's persistent state, while a separate plain `Codable` snapshot feeds the widget. Times are stored as minutes after midnight plus weekday, so the same class repeats every week without date math.

| Model | Type | Key fields | Notes |
| --- | --- | --- | --- |
| `UserProfile` | `@Model` | id, displayName, handle, joinedClubIDs, rsvpedInviteIDs, isVerifiedMember | The signed-in user; one demo user in MVP |
| `ClassSchedule` | `@Model` | courseCode, title, section, units, weekdays, startMinutes, endMinutes, building, room, startDate, endDate, professor | One row per course; repeats weekly between start and end dates |
| `ProfessorInfo` | `Codable` struct, embedded | name, overallRating, difficulty, wouldTakeAgainPercent, topTags | Embedded in `ClassSchedule`, not its own table; looked up by name from seed data |
| `FreeSlot` | plain struct | weekday, startMinutes, endMinutes, label | Computed, never persisted; used by timetable and overlap |
| `OpenInvite` | `@Model` | id, title, landmark, category, startTime, expiresAt, hostName, attendeeIDs, capacity | Expired when now > expiresAt; filtered at read time |
| `ClubEvent` | `@Model` | id, clubName, title, details, location, startTime, access, duesAmount | `access` is an enum: public, membersOnly, duesRequired |
| `FriendProfile` | `@Model` | id, displayName, classes | Demo friend for the overlap view |
| `WidgetSnapshot` | `Codable` | nextBlock, topInvite, generatedAt | Written as JSON to the App Group; the widget reads only this |

**Supporting enums:** `Weekday`, `InviteCategory` (food, study, fitness, social, each with color and symbol), `ClubAccess`, `Landmark` (The Pit, Chase Dining Hall, Davis Library, and so on, each with a display name and symbol).

**Decisions to confirm**

- Store invite expiry as an absolute `Date`, not a duration, so the widget can compute it without the app running.
- Keep `ProfessorInfo` out of SwiftData so changing mock scores never needs a migration.

## 6. Features, screens, and design system

The app is a four-tab `TabView` with chunky cards and large tap targets, built to be used one-handed while walking.

**Design system (`Theme.swift`)**

| Token | Value | Use |
| --- | --- | --- |
| Carolina Blue | `#7BAFD4` | Primary brand, buttons, selected tab |
| Navy | `#13294B` | Headings and dark-mode surfaces |
| Slate grays | system grays | Secondary text, dividers |
| Food / Study / Fitness / Social | orange, indigo, green, pink | Category pills; always paired with a symbol so color is not the only signal |
| Card style | 20 pt radius, 16 pt padding, 44 pt minimum tap target | Shared `CardStyle` modifier |

Support dark mode from the start by using asset-catalog colors instead of hard-coded hex values. Check that Carolina Blue text on white meets contrast requirements; use it for fills and use Navy for text.

**Tab 1: Home**

- Live Status banner: current or next class with a countdown, plus the gap summary ("45 min free before COMP 433").
- Horizontal carousel of active invites from friends, soonest first.

**Tab 2: Schedule**

- Segmented control: My Schedule and Friend Overlap.
- My Schedule is a weekly timetable grid with class blocks and shaded free gaps. Tapping a class opens `ProfessorRatingSheet` (overall rating, difficulty, would-take-again %, top tags).
- Friend Overlap picks a friend and highlights mutual free slots, longest first, with a "Make an invite for this slot" action.
- A PDF import button sits in the toolbar and on the empty state.

**Tab 3: Friend Invites**

- Feed grouped by time, each card showing landmark, category pill, countdown, attendee count, and an RSVP button that toggles. Only friends you have added can be invited; the poster picks who gets each plan. In the demo, friends come from seed data and a real add-friend flow is stretch.
- Floating "+ Post" opens a compose sheet: title, landmark picker, category, start time, duration. Defaults should make posting a two-tap action.
- Cards disappear when `expiresAt` passes.

**Tab 4: Clubs**

- Feed of GBMs and events with access badges: Public, Members Only, Dues Required. Club events are public, and members who subscribe are notified.
- Dues Required cards show a one-tap "Pay Dues" button that flips local state, shows a confirmation, and adds a "Verified Member" badge to the profile.

**Widget (`ScheduleWidget.swift`)**

- Families: `systemSmall`, `systemMedium` for the Home Screen, and `accessoryRectangular`, `accessoryCircular`, `accessoryInline` for the Lock Screen. The original two families alone do not cover the Lock Screen.
- Small: next class or free block with a countdown. Medium: that block plus the top friend invite with landmark and time.
- The `TimelineProvider` builds several entries ahead of time, one at each boundary (a class starting, a class ending, an invite expiring), and sets a reload policy for the next boundary. It cannot update continuously.
- The app calls `reloadAllTimelines()` after any local write (new invite, RSVP, import). Tapping the widget deep-links to the relevant tab.

## 7. Seed data and demo plan

The demo user's schedule should be the real sample schedule, so the PDF import and the "Load demo schedule" fallback produce the same result. Everything else is fictional.

**Demo user schedule (from the sample PDF, Fall 2026, 08/17 to 12/11)**

| Course | Title | Days | Time | Room |
| --- | --- | --- | --- | --- |
| COMP 523 | Software Engineering Lab | Mon, Wed | 1:25 PM to 2:40 PM | Sitterson Hall, FB009 |
| COMP 433 | Mobile Computing Systems | Tue, Thu | 11:00 AM to 12:15 PM | Sitterson Hall, SN014 |
| COMP 577 | Intro to Computer Vision | Tue, Thu | 3:30 PM to 4:45 PM | Sitterson Hall, FB009 |
| LING 460 | Textual Analysis with R | Tue, Thu | 5:00 PM to 6:15 PM | Fetzer Hall, 0109 |

This schedule produces useful gaps for the demo: Tuesdays and Thursdays have a 3 h 15 min gap from 12:15 PM to 3:30 PM and a 15-minute scramble from 4:45 PM to 5:00 PM. Mondays and Wednesdays are free until 1:25 PM, and Fridays are entirely free.

**Fictional seed content**

- **Friends:** two or three demo friends with schedules built to overlap your Tuesday/Thursday afternoon gap, so the overlap view always shows a clear mutual window.
- **Professor ratings:** invented values for each primary instructor, shown with a visible "Demo data" footer. Do not present them as real RateMyProfessor scores.
- **Friend invites:** 5 to 6, with start times defined relative to launch time (now plus 20 min, plus 45 min, and so on) so they are never expired when judges open the app. Mix categories and landmarks: Chase Dining Hall dinner, Davis Library study group, The Pit hangout, a pickup game.
- **Clubs:** 4 to 5 invented organizations, one per access type, with upcoming GBMs and events. Avoid names of real student orgs.

**Demo script (90 seconds)**

1. Open the app on the Home tab: live status banner shows the current gap and the next class.
2. Import the ConnectCarolina PDF and show the parsed timetable.
3. Open Friend Overlap and show the mutual free window.
4. Tap "Make an invite for this slot" and send a Friend Invite.
5. Go to the Home Screen: the widget now shows the new invite.
6. Show the Lock Screen widget.
7. Finish on Clubs: tap Pay Dues and show the Verified Member badge.

**Demo safety net**

- A hidden developer menu (triple-tap the profile avatar) with a time override, so the demo can run "as if it is Tuesday at 12:30 PM" regardless of the real clock.
- A reset-to-seed button that regenerates relative invite times.
- A pre-recorded screen capture of the full flow, in case the device or Wi-Fi fails.

## 8. Build order, files, and team split

Build the vertical slice that powers the demo first, then add features in order of demo impact. This single list replaces the overlapping file lists in the earlier prompts. Hour estimates are rough planning figures for a two-person team.

| Phase | Goal | Files | Suggested owner | Est. hours |
| --- | --- | --- | --- | --- |
| 0. Setup | Project, widget target, App Group, shared entitlements | Xcode targets, `AppGroupManager.swift` | Both | 1 |
| 1. Foundation | Models, theme, seed data, repository protocols | `Models.swift`, `Theme.swift`, `SampleData.swift`, `Repositories.swift` | Person A | 3 |
| 2. Shell | Four-tab navigation with placeholder screens | `MainTabView.swift`, `HomeDashboardView.swift` | Person B | 2 |
| 3. Schedule | Timetable grid, free-slot calculation, professor sheet | `TimetableView.swift`, `ScheduleViewModel.swift`, `ProfessorRatingSheet.swift` | Person A | 5 |
| 4. Friend Invites | Feed, card, compose, RSVP, expiry | `OpenInviteCardView.swift`, `InvitesViewModel.swift`, `ComposeInviteSheet.swift` | Person B | 5 |
| 5. Widget | Snapshot writer, timeline provider, all families | `ScheduleWidget.swift`, `WidgetSnapshot.swift` | Person B | 5 |
| 6. PDF import | Parser, confirmation screen, demo fallback | `ScheduleImporter.swift`, `ConnectCarolinaPDFParser.swift`, `ImportReviewView.swift` | Person A | 5 |
| 7. Overlap | Overlap algorithm and view | `FriendScheduleOverlayView.swift`, `OverlapEngine.swift` | Person A | 3 |
| 8. Clubs | Feed, access badges, Pay Dues state | `ClubEventCardView.swift`, `ClubsViewModel.swift` | Person B | 3 |
| 9. Polish | Dark mode, empty states, dev menu, time override, demo recording | Dev menu, assets | Both | 4 |
| 10. Stretch | `.ics` import, Firestore repositories, Auth | `ICSParser.swift`, Firebase repositories | Whoever is free | Optional |

**Cut order if time runs short:** Clubs polish, then overlap polish, then PDF import (fall back to demo schedule), then widget families beyond small and medium. Do not cut the widget or Friend Invites; they are the pitch.

**Working agreements**

- Agree on `Models.swift` before either person builds views, and treat it as frozen after phase 1 except for additive fields.
- Commit to separate files per feature to avoid merge conflicts in the Xcode project file; use one person to add targets and capabilities.
- Test on a physical device by phase 5, since widgets and Lock Screen behavior are unreliable in the simulator.

## 9. Improvements, risks, and polish

The highest-risk items are the PDF parser, the widget behavior on a real device, and the clock during the demo. Fix those first.

| # | Area | Issue | Fix | Priority |
| --- | --- | --- | --- | --- |
| 1 | PDF parsing | Parser is designed from one sample; text extraction order from PDFKit is untested | Run PDFKit on the sample in hour one, print the raw string, and write the regexes against it | Must fix |
| 2 | Demo clock | Today is a Saturday, so "next class" and "free now" would show Monday; invites expire in real time | Add a time override and relative seed times (section 7) | Must fix |
| 3 | Lock Screen | `systemSmall` and `systemMedium` do not appear on the Lock Screen | Add the three accessory families | Must fix |
| 4 | Widget refresh | Widgets cannot update continuously; reload budgets are limited | Pre-build timeline entries at class and invite boundaries; reload on local writes | Must fix |
| 5 | Real-world schedules | Sample has four simple courses; real PDFs include `TBA` times, online sections, multiple meeting rows per course, Saturday classes | Handle `TBA`/missing times by skipping the row, support multiple meetings per course, and show a review screen before saving | Should fix |
| 6 | Free-slot rules | A 15-minute gap is not usable free time, and campus walking time is ignored | Set a minimum gap (for example 30 min), a waking-hours window (for example 8 AM to 10 PM), and a configurable walking buffer | Should fix |
| 7 | Privacy | The PDF contains the student's name and university ID; friend schedules are sensitive | Parse only the term and courses, never store the ID, exclude real PDFs from git, and show "share my schedule with" controls | Should fix |
| 8 | Invite safety | Open posts to a whole campus invite spam and meeting strangers | Default to friends-only visibility, keep public landmarks only, add a report button; mention this in the pitch | Should fix |
| 9 | Professor data | The Instructor field includes co-instructors and TAs; mock ratings could be read as real | Use first-listed name, label "Instructor", and show a "Demo data" footer | Should fix |
| 10 | Semester breaks | Dates cover 08/17 to 12/11 but not holidays or fall break | Ignore for MVP; note as a future calendar-feed integration | Later |
| 11 | Accessibility | Color-coded pills and dense timetable grid | Pair color with symbols, support Dynamic Type, add VoiceOver labels to class blocks | Should fix |
| 12 | Firebase | Real-time sync needs security rules, friend permissions, and a Wi-Fi-independent demo | Keep behind repository protocols; write rules before enabling public writes | Later |
| 13 | Snapshot versioning | App and widget can disagree after an update | Include a `version` field in `WidgetSnapshot` and fail safe to an empty state | Later |
| 14 | Naming and IDs | `group.com.yourname.app` is a placeholder; it must match in both entitlements and in code | Pick the final name and bundle ID before creating targets | Must fix |

**Pitch polish**

- Lead with the problem in one sentence ("you have a free gap and so do your friends, but nobody knows") and show the widget in the first ten seconds.
- Pitch the PDF upload as zero-setup onboarding: no calendar permissions, no account linking, everything parsed on the device.
- Name the next steps honestly: friend graph, real sync, other universities' schedule formats.

**Open questions for the team**

- Decided: the demo is a recorded run on a physical iPhone with Wi-Fi. Test widgets and the Lock Screen on that device early, since signing and App Group setup can differ by account type. Wi-Fi lowers the risk of adding Firestore, but keep seed data as the default so the recording never depends on it.
- Decided: club events go to everyone who has joined or subscribed to the club, while Friend Invites go only to friends you have added, whom you invite through the app. Club events are public and subscribers are notified.
- Final app name?
