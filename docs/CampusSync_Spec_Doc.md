# CampusSync: HackNC Master Spec

Oct 10, 2026 · @tri · Revised: live Firebase backend, online demo

## 1. Overview

CampusSync (working name, lock it before creating bundle IDs) is a native iOS app that tells UNC Chapel Hill students when they and their friends are free, and what is happening on campus right now. It targets three frictions: schedule gaps nobody notices, club events nobody finds, and spontaneous plans that never get made.

**The hook:** a Home Screen and Lock Screen widget shows your next class or free block plus the top friend invite, without opening the app. It reads from a shared on-device container, so it never touches the network.

**Four pillars**

- **Schedule engine.** Upload your ConnectCarolina class schedule PDF, parse it on-device into `ClassSchedule` models, and see a weekly timetable with class blocks and free gaps. Tapping a class opens a professor rating sheet with real RateMyProfessors ratings (cached and credited).
- **Friend overlap.** Compare two weekly schedules and highlight mutual free windows (`FreeSlot`).
- **Friend Invites.** Time-boxed plans you send only to friends you have added in the app, tied to campus landmarks (The Pit, Chase Dining Hall, Davis Library) with category tags (Food, Study, Fitness, Social), RSVP, and auto-expiration.
- **Clubs Hub.** A feed of GBMs and events with access badges (Public, Members Only, Dues Required) and a one-tap Join Club / Pay Dues action.

**Stack:** Swift 5.9+, iOS 17+, SwiftUI, SwiftData, MVVM, WidgetKit, App Groups, and Firebase Auth + Firestore as the live backend behind repository protocols. SwiftData is the on-device store and cache; Firestore is the source of truth for accounts, friends, invites, clubs and shared schedules. The demo runs online on real accounts and real data.

## 2. Scope and locked decisions

The app is built as a live product, not a mocked demo: real accounts, a real friend graph, and data that syncs between phones. The demo runs online on a physical iPhone. Seed data remains only as a dev, preview, test and fallback aid. These decisions replace the contradictions in the earlier drafts, including the earlier "mock first, Firebase only if time permits" plan.

**Decisions**

1. **Firebase is the live backend.** All data access goes through repository protocols (`UserRepository`, `ScheduleRepository`, `InviteRepository`, `ClubRepository`, plus friend access). The Firestore implementations are the real ones. The local SwiftData implementations stay for previews, tests and offline fallback, and the app must still launch and be usable with no connection.
2. **Schedule import is a ConnectCarolina PDF upload.** The student prints or saves their class schedule from ConnectCarolina as a PDF and imports it. `.ics` becomes a secondary importer, not the headline.
3. **No Apple Pay or PassKit.** Dues are a one-tap "Pay Dues" button that records a membership in Firestore and shows a "Verified Member" badge. No real payments.
4. **"Nearby" means tagged to a campus landmark.** No Core Location.
5. **Widget refresh is local.** The app calls `WidgetCenter.shared.reloadAllTimelines()` on local writes, on foreground, and whenever a Firestore listener delivers a change. The widget itself never touches Firebase or the network. Because there are no push notifications in the MVP, the widget shows changes made by friends after the app next runs or foregrounds. Background push is a stretch item.
6. **One shared container strategy:** a small Codable JSON snapshot in the App Group, not a shared SwiftData store and not a Firebase SDK inside the widget.
7. **Sign-in is email and password, restricted to `@unc.edu` addresses,** with a verification email, using Firebase Auth. The restriction is enforced in the app and again in Firestore security rules.
8. **Friends are added by handle search with request and accept.** A student searches a unique `@handle`, sends a request, and the other student accepts. Friend Invites and shared schedules only ever go to accepted friends.
9. **Professor ratings come from RateMyProfessors.** They are fetched by instructor name, cached on device, credited on screen, and fall back to "no rating". The lookup is unofficial, so it stays isolated behind `ProfessorRatingProvider`.

**Scope table**

| Feature | Tier | MVP approach |
| --- | --- | --- |
| PDF schedule import + timetable | MVP | PDFKit text extraction, regex parser, demo schedule fallback |
| Accounts (Firebase Auth) | MVP | Email and password, `@unc.edu` only, email verification |
| Friends: search, request, accept | MVP | Firestore handles and friend requests, enforced by security rules |
| Friend overlap | MVP | Friend's shared meetings read from Firestore; overlap computed locally |
| Friend Invites feed, RSVP, expiry | MVP | Firestore invites, real-time listener, expired invites filtered at read time |
| Widget (small, medium, Lock Screen) | MVP | JSON snapshot in App Group, timeline entries at known boundaries |
| Professor rating sheet | MVP | RateMyProfessors lookup, cached on device, credited on screen |
| Clubs feed + access badges | MVP | Firestore clubs and events, one-tap Join / Pay Dues writes a membership |
| Firestore security rules + emulator tests | MVP | Written and tested before real users can write |
| Seed data and seeding script | MVP (dev and demo) | Fictional clubs, events and demo accounts loaded into Firestore by a script; local seed for previews and tests |
| `.ics` import | Stretch | Simple parser, no recurrence support at first |
| Push notifications (FCM) | Stretch | So the widget and club subscribers update without opening the app |
| Report and block | Stretch | Needed before wide release; mentioned in the pitch |
| PassKit membership pass | Deferred | Static badge instead |
| Apple Pay sheet | Deferred | One-tap button instead |
| Club treasury visualizer | Deferred | Static descriptions |

## 3. Architecture

The app and the widget share data through one JSON snapshot in the App Group container, and everything else stays inside the main app.

&#91;embedded content: architecture layers · app, widget, shared snapshot\]

The app writes the snapshot after any local change and asks WidgetKit to reload; the widget's `TimelineProvider` only ever reads that file.

**Layer rules**

- Views talk only to ViewModels, and ViewModels talk only to repository protocols and the logic layer, never to SwiftData directly.
- The widget target shares only `WidgetSnapshot` and the theme with the app. It does not open the SwiftData store.
- Firestore repositories are the real implementations of the same protocols. The local SwiftData repositories stay for previews, tests and offline fallback.

**Data flows**

1. **Schedule import.** Student picks the ConnectCarolina PDF, PDFKit extracts the text, `ConnectCarolinaPDFParser` produces `ClassSchedule` models, the student confirms them on a review screen, they save to SwiftData, and the app rewrites the snapshot and reloads the widget.
2. **Schedule overlap.** Student picks a friend, the app loads that friend's shared meetings from Firestore, `OverlapEngine` intersects both free-slot lists on the device, and the overlay view renders the mutual windows.
3. **Friend invite.** Student posts an invite, the repository saves it, the invites feed refreshes, the app writes the new top invite into the snapshot, and `reloadAllTimelines()` updates the widget. The Firestore listener delivers other students' invites and triggers the same path, so a friend's new invite reaches the snapshot and widget the next time the app runs.

### Firebase backend

Firebase Auth and Firestore are the source of truth. The app uses the Firebase iOS SDK (Swift Package Manager, `FirebaseAuth` and `FirebaseFirestore` only). The widget target links no Firebase code.

**Auth.** Email and password. The app rejects non-`@unc.edu` addresses, sends a verification email, and blocks Firestore access until the email is verified. Security rules check `request.auth.token.email_verified` and the `@unc.edu` suffix again, so the client is not trusted.

**Firestore data model (proposed)**

| Path | Contents | Who can read | Who can write |
| --- | --- | --- | --- |
| `users/{uid}` | displayName, handle, createdAt | Any verified user (needed for handle search) | The owner |
| `handles/{handle}` | uid | Any verified user | Create-only by the owner, which keeps handles unique |
| `friendRequests/{fromUID}_{toUID}` | fromUID, toUID, status, createdAt | The two people involved | Sender creates (pending only, id fixes one request per direction); recipient accepts or declines; sender cancels, either deletes once answered |
| `users/{uid}/friends/{friendUID}` | since | The owner | Written for both people in one batch when a request is accepted, allowed only if an accepted request exists; either person can delete both sides (unfriend) |
| `schedules/{uid}/meetings/{n}` | One document per class meeting: courseCode, weekdays, startMinutes, endMinutes, building (exact keys enforced by the rules, so a title or instructor cannot be stored) | The owner and accepted friends (proved by `users/{uid}/friends/{viewer}` existing) | The owner |
| `invites/{id}` | hostID, hostName, title, landmark, category, startTime, expiresAt, attendeeIDs, recipientIDs, capacity | The host and the listed recipients | Host creates, with `hostID == auth.uid`, `hostName` equal to the host's profile name, `expiresAt > startTime`, capacity 2 to 50, 1 to 30 recipients; the host or a recipient may only add or remove themselves in `attendeeIDs`, within capacity; only the host deletes. Rules cannot loop over `recipientIDs`, so "recipients are all friends" is enforced by the app, not the rules |
| `clubs/{clubID}` and `clubs/{clubID}/events/{eventID}` | name, summary, symbol, access, duesAmount; event title, details, location, startTime, access, duesAmount | Any verified user | Admin seeding script only (`firebase/seed/seed.mjs`); clients are denied |
| `users/{uid}/memberships/{clubID}` | joinedAt, duesPaid | The owner | The owner; the club must exist; `duesPaid` can only be set (false to true) on a dues-required club |

Notes on the model:
- The shared schedule document holds meeting times only. It never holds course titles, instructor names, the student's name, or any university ID, so a friend sees when you are busy and nothing more.
- Query invites with `recipientIDs array-contains uid` and `expiresAt > now`, backed by a composite index. Clients also filter expired invites at read time, and a Firestore TTL policy on `expiresAt` deletes old documents.
- The existing models map across: `OpenInvite` to `invites`, `FriendProfile` to a cached copy of a friend's `schedules` document, `UserProfile.friendIDs` to the `friends` subcollection, and `Club` and `ClubEvent` to `clubs` and `events`.

**Sync (as built).** `SyncCoordinator` owns the listeners (my hosted invites, invites I was sent, my friends, my memberships, the clubs collection) and mirrors results into the SwiftData cache; the Firestore repositories read the cache and send writes to Firestore without waiting for the server, so Firestore's offline queue holds them. Friends' shared meetings are fetched when the friend list changes and on app foreground or pull to refresh. Sign-out stops the listeners and wipes the cache. Original plan: each Firestore repository exposes an async API plus a snapshot listener. ViewModels consume the listener, the repository mirrors results into the local store for offline use, and any change triggers the widget snapshot rewrite and `reloadAllTimelines()`. Firestore's offline persistence is on, so recently seen data keeps working with no connection.

**Security rules.** Rules live in the repo (`firebase/firestore.rules`) with indexes (`firebase/firestore.indexes.json`) and are tested in the Firebase emulator before any real write is allowed. `GoogleService-Info.plist` and any service account key are never committed.

**Scale notes.** Listeners are scoped to the signed-in user's own invites, friends and requests, never whole collections. Denormalize `hostName` onto invites to avoid joins. Paginate the clubs feed. Keep the Spark (free) plan limits in mind for the demo, and treat App Check and a cost review as a pre-launch item.

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
| `UserProfile` | `@Model` | id, displayName, handle, friendIDs, joinedClubIDs, rsvpedInviteIDs, isVerifiedMember | The signed-in user, mirrored from Firebase Auth and Firestore |
| `ClassSchedule` | `@Model` | courseCode, title, section, units, weekdays, startMinutes, endMinutes, building, room, startDate, endDate, professor | One row per course; repeats weekly between start and end dates |
| `ProfessorInfo` | `Codable` struct, embedded | name, overallRating, difficulty, wouldTakeAgainPercent, topTags | Unused. Superseded by `ProfessorRating`, a non-persisted value fetched from RateMyProfessors and cached on device |
| `FreeSlot` | plain struct | weekday, startMinutes, endMinutes, label | Computed, never persisted; used by timetable and overlap |
| `OpenInvite` | `@Model` | id, title, landmark, category, startTime, expiresAt, hostName, attendeeIDs, capacity | Expired when now > expiresAt; filtered at read time |
| `ClubEvent` | `@Model` | id, clubName, title, details, location, startTime, access, duesAmount | `access` is an enum: public, membersOnly, duesRequired |
| `FriendProfile` | `@Model` | id, displayName, classes | Local cache of an accepted friend's shared meetings, synced from Firestore, used by the overlap view |
| `WidgetSnapshot` | `Codable` | nextBlock, topInvite, generatedAt | Written as JSON to the App Group; the widget reads only this |

**Supporting enums:** `Weekday`, `InviteCategory` (food, study, fitness, social, each with color and symbol), `ClubAccess`, `Landmark` (The Pit, Chase Dining Hall, Davis Library, and so on, each with a display name and symbol).

**Decisions to confirm**

- Store invite expiry as an absolute `Date`, not a duration, so the widget can compute it without the app running.
- Keep rating data out of SwiftData so RateMyProfessors changes never need a migration.

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

**Profile header (every tab).** Initials avatar (tap for Account and Friends), `@handle`, the UNC logo, a "Verified Member" pill once dues are paid, and "CS '28 · Free Tue/Thu 12:15–3:30". Major and class year are optional profile fields; the free window is the longest gap between classes that repeats on the same days.

**Tab 1: Home.** One scroll: a blue "FREE NOW" hero (time until the next class, or the class you are in); a collapsible "Today · 4 classes" card; a horizontal row of "Friends free now" cards, one per friend, each with an avatar, a status line and a pill (Mutual Window, Free Now, In Class, or No Schedule when they share nothing; mutual windows first; pull down to refresh; tap to open that friend in Schedule > Friends); then a carousel of active invites with RSVP.

**Tab 2: Schedule.** Segments: Timetable, Friends, Classes.
- Timetable: Mon to Fri chips (today by default) and one scrollable day (8 AM to 10 PM): class blocks and dashed "Free · 3 h 15 min" boxes.
- Friends: a row of friend avatars (one at a time) showing each friend's longest shared free time that day, the same day chips, and a two-column "You | Maya" timeline. The friend's blocks say only "Class". Mutual free time is outlined across both columns; tapping a window starts an invite for it (start at the window's next start, 60 minutes or what fits, only that friend).
- Classes: a card per class with the first-listed instructor's RateMyProfessors rating inline (rating pill colored green at 4.0 and above, amber 3.0 to 3.9, red below 3.0; difficulty; would take again; number of ratings; "Low count" under 5 ratings). Real, cached, credited ratings only.

**Tab 3: Invites.** Category chips (All, Food, Study, Fitness, Social), a flat list soonest first ("Maya + 2 going", RSVP), and a navy "+ Post" button. Only friends you have added can be invited. Cards disappear when `expiresAt` passes.

**Tab 4: Clubs.** A feed of upcoming club events (events are public). Each card shows the club with an access badge (Public, Dues Required · $25, Members Only), the event, date and time, location, and whether it fits your classes ("You are free then" or "Conflicts with LING 460 · 5:00–6:15 PM"), plus Join Club or Pay Dues. Filters: All clubs, Free for me, Joined. Pay Dues records a membership flag and shows Verified Member; no real payment.

**Widget (`ScheduleWidget.swift`)**

- Families: `systemSmall`, `systemMedium` for the Home Screen, and `accessoryRectangular`, `accessoryCircular`, `accessoryInline` for the Lock Screen. The original two families alone do not cover the Lock Screen.
- Small: next class or free block with a countdown. Medium: that block plus the top friend invite with landmark and time.
- The `TimelineProvider` builds several entries ahead of time, one at each boundary (a class starting, a class ending, an invite expiring), and sets a reload policy for the next boundary. It cannot update continuously.
- The app calls `reloadAllTimelines()` after any local write (new invite, RSVP, import). Tapping the widget deep-links to the relevant tab.

## 7. Demo data and demo plan

The demo runs online against the real Firebase project with real accounts. Seed data supports development and the safety net, and a seeding script loads the fictional clubs and events into Firestore, since there is no admin screen. The demo user's schedule is the real sample schedule, so the PDF import and the "Load demo schedule" fallback produce the same result.

**Demo user schedule (from the sample PDF, Fall 2026, 08/17 to 12/11)**

| Course | Title | Days | Time | Room |
| --- | --- | --- | --- | --- |
| COMP 523 | Software Engineering Lab | Mon, Wed | 1:25 PM to 2:40 PM | Sitterson Hall, FB009 |
| COMP 433 | Mobile Computing Systems | Tue, Thu | 11:00 AM to 12:15 PM | Sitterson Hall, SN014 |
| COMP 577 | Intro to Computer Vision | Tue, Thu | 3:30 PM to 4:45 PM | Sitterson Hall, FB009 |
| LING 460 | Textual Analysis with R | Tue, Thu | 5:00 PM to 6:15 PM | Fetzer Hall, 0109 |

This schedule produces useful gaps for the demo: Tuesdays and Thursdays have a 3 h 15 min gap from 12:15 PM to 3:30 PM and a 15-minute scramble from 4:45 PM to 5:00 PM. Mondays and Wednesdays are free until 1:25 PM, and Fridays are entirely free.

**Demo data setup (do this before recording)**

- **Accounts:** create two or three real `@unc.edu` test accounts ahead of time (one per device or simulator), verify their emails, and make them friends through the real request and accept flow.
- **Schedules:** each account imports a schedule so the overlap view has a clear mutual window. The main account imports the real sample PDF. The others can use the demo schedule or a PDF of their own. Share only meetings, as described in the data model.
- **Professor ratings:** real RateMyProfessors ratings, fetched and cached before the demo so they appear instantly, shown with the RateMyProfessors credit.
- **Clubs:** 4 to 5 invented organizations, one per access type, with upcoming GBMs and events, loaded into Firestore by the seeding script. Avoid names of real student orgs.
- **Friend invites:** post a few real invites just before the recording so none are expired when the demo runs. The seeding script can also create a batch with times relative to the run.

**Demo script (90 seconds)**

1. Open the app on the Home tab, already signed in: live status banner shows the current gap and the next class.
2. Import the ConnectCarolina PDF and show the parsed timetable.
3. Open Friend Overlap and show the mutual free window.
4. Tap "Make an invite for this slot" and send a Friend Invite.
5. Go to the Home Screen: the widget now shows the new invite.
6. Show the Lock Screen widget.
7. Finish on Clubs: tap Pay Dues and show the Verified Member badge.

**Demo safety net**

- A hidden developer menu (triple-tap the profile avatar) with a time override, so the demo can run "as if it is Tuesday at 12:30 PM" regardless of the real clock.
- A reset-demo-data action and a seeding script that recreate the clubs, events and invites with fresh times.
- Local fallback: the SwiftData repositories and seed data still work with no connection, so a network failure degrades the app instead of breaking it.
- A pre-recorded screen capture of the full flow, in case the device or Wi-Fi fails.

## 8. Build order, files, and team split

Build the vertical slice that powers the demo first, then add features in order of demo impact. This single list replaces the overlapping file lists in the earlier prompts. Hour estimates are rough planning figures for a two-person team.

| Phase | Goal | Files | Suggested owner | Est. hours |
| --- | --- | --- | --- | --- |
| 0. Setup | Project, widget target, App Group, shared entitlements | Xcode targets, `AppGroupManager.swift` | Both | 1 |
| 1. Foundation | Models, theme, clock, seed data, repository protocols | `Models.swift`, `Theme.swift`, `AppClock.swift`, `SampleData.swift`, `Repositories.swift` | Person A | 3 |
| 2. Shell | Four-tab navigation with placeholder screens | `MainTabView.swift`, `HomeDashboardView.swift` | Person B | 2 |
| 3. Schedule | Timetable grid, free-slot calculation, professor sheet | `TimetableView.swift`, `ScheduleViewModel.swift`, `ProfessorRatingSheet.swift` | Person A | 5 |
| 4. Friend Invites | Feed, card, compose, RSVP, expiry | `OpenInviteCardView.swift`, `InvitesViewModel.swift`, `ComposeInviteSheet.swift` | Person B | 5 |
| 5. Widget | Snapshot writer, timeline provider, all families | `ScheduleWidget.swift`, `WidgetSnapshot.swift` | Person B | 5 |
| 6. PDF import | Parser, review screen, demo fallback, RateMyProfessors ratings | `ConnectCarolinaPDFParser.swift`, `ImportReviewView.swift`, `RateMyProfessorClient.swift` | Person A | 5 |
| 7. Firebase foundation | Firebase project and SDK, Auth sign up and sign in (`@unc.edu`), user profile and handles, security rules and emulator tests | `firebase/firestore.rules`, auth views, `AuthService.swift` | Both | 6 |
| 8. Sync and friends | Friend search, request and accept, Firestore repositories for schedule, invites and clubs, listeners feeding the snapshot writer, seeding script | `Firestore*Repository.swift`, friends views, `firebase/seed` | Both | 8 |
| 9. Overlap | Overlap algorithm and view over real friends' schedules (now Schedule > Friends) | `FriendScheduleOverlayView.swift`, `OverlapEngine.swift` | Person A | 3 |
| 10. UI redesign | The six supplied PDF designs: shared header, Home, Schedule (Timetable, Friends, Classes), Invites, Clubs feed. Absorbs the old Clubs phase | `AppHeader.swift`, `ClassesListView.swift`, `ClubEventCardView.swift`, `ClubsViewModel.swift` | Person B | 8 |
| 10b. Design perfecting | Fix UI issues found on physical phones against the designs; then commit and push phases 9 and 10 | Views as needed | Both | 3 |
| 10c. Clubs live | Seed the real project's clubs and events, verify Join and Pay Dues on device (deferred) | `firebase/seed` | Both | 1 |
| 11. Polish | Dark mode, empty states, dev menu, time override, demo recording | Dev menu, assets | Both | 4 |
| 12. Stretch | `.ics` import, push notifications (FCM), report and block, App Check | `ICSParser.swift`, push setup | Whoever is free | Optional |

**Status (2026-10-10):** phases 0 to 10b are committed and pushed; the user signed off the UI on two physical phones. The Firestore rules for the redesign (optional major and class year) are deployed; clubs are not seeded on the real project, and the widget is deliberately untouched.

**Cut order if time runs short:** Clubs polish, then overlap polish, then PDF import (fall back to demo schedule), then widget families beyond small and medium. Do not cut the widget, Friend Invites, or real accounts and sync; they are the pitch. If Firebase work slips, the local repositories and seed data remain as the fallback, but the plan is to demo on real networking.

**Working agreements**

- Agree on `Models.swift` before either person builds views, and treat it as frozen after phase 1 except for additive fields.
- Commit to separate files per feature to avoid merge conflicts in the Xcode project file; use one person to add targets and capabilities.
- Test on a physical device by phase 5, since widgets and Lock Screen behavior are unreliable in the simulator.
- Write and emulator-test the Firestore security rules before enabling any real write. Never commit `GoogleService-Info.plist` or a service account key.

## 9. Improvements, risks, and polish

The highest-risk items are the PDF parser, the widget behavior on a real device, and the clock during the demo. Fix those first.

| # | Area | Issue | Fix | Priority |
| --- | --- | --- | --- | --- |
| 1 | PDF parsing | Parser is designed from one sample; text extraction order from PDFKit is untested | Run PDFKit on the sample in hour one, print the raw string, and write the regexes against it | Must fix |
| 2 | Demo clock | Today is a Saturday, so "next class" and "free now" would show Monday; invites expire in real time | Add a time override and relative invite times in the seeding script (section 7) | Must fix |
| 3 | Lock Screen | `systemSmall` and `systemMedium` do not appear on the Lock Screen | Add the three accessory families | Must fix |
| 4 | Widget refresh | Widgets cannot update continuously; reload budgets are limited | Pre-build timeline entries at class and invite boundaries; reload on local writes | Must fix |
| 5 | Real-world schedules | Sample has four simple courses; real PDFs include `TBA` times, online sections, multiple meeting rows per course, Saturday classes | Handle `TBA`/missing times by skipping the row, support multiple meetings per course, and show a review screen before saving | Should fix |
| 6 | Free-slot rules | A 15-minute gap is not usable free time, and campus walking time is ignored | Set a minimum gap (for example 30 min), a waking-hours window (for example 8 AM to 10 PM), and a configurable walking buffer | Should fix |
| 7 | Privacy | The PDF contains the student's name and university ID; friend schedules are sensitive | Parse only the term and courses, never store the ID, exclude real PDFs from git, and show "share my schedule with" controls | Should fix |
| 8 | Invite safety | Open posts to a whole campus invite spam and meeting strangers | Default to friends-only visibility, keep public landmarks only, add a report button; mention this in the pitch | Should fix |
| 9 | Professor data | The Instructor field includes co-instructors and TAs; a name match on RateMyProfessors can pick the wrong person | Use first-listed name, label "Instructor", match on full name, link to the RateMyProfessors page, and say the match is by name | Should fix |
| 10 | Semester breaks | Dates cover 08/17 to 12/11 but not holidays or fall break | Ignore for MVP; note as a future calendar-feed integration | Later |
| 11 | Accessibility | Color-coded pills and dense timetable grid | Pair color with symbols, support Dynamic Type, add VoiceOver labels to class blocks | Should fix |
| 12 | Firebase | Real-time sync needs security rules, friend permissions, and a plan for a flaky network | Keep behind repository protocols; write and emulator-test rules before enabling writes; keep local fallback and a recorded demo | Must fix |
| 13 | Snapshot versioning | App and widget can disagree after an update | Include a `version` field in `WidgetSnapshot` and fail safe to an empty state | Later |
| 14 | Naming and IDs | `group.com.yourname.app` is a placeholder; it must match in both entitlements and in code | Pick the final name and bundle ID before creating targets | Must fix |
| 15 | Account abuse | Anyone could sign up and search for people | Restrict to verified `@unc.edu` emails in the app and in rules; searchable fields limited to handle and display name | Must fix |
| 16 | Schedule sharing | Friends' schedules are sensitive | Share meeting times only, to accepted friends only; never course titles, instructors, or IDs; provide a way to stop sharing | Must fix |
| 17 | RateMyProfessors | No official API; the unofficial lookup may change or stop | Isolate behind `ProfessorRatingProvider`, cache results, credit the source, degrade to "no rating" | Should fix |
| 18 | Cost and scale | Listeners and reads grow with users | Scope listeners to the user's own data, paginate, use TTL cleanup; review quota and add App Check before launch | Later |

**Pitch polish**

- Lead with the problem in one sentence ("you have a free gap and so do your friends, but nobody knows") and show the widget in the first ten seconds.
- Pitch the PDF upload as zero-setup onboarding: no calendar permissions, no account linking, everything parsed on the device. Be clear that only meeting times are shared, and only with friends you accept.
- Name the next steps honestly: push notifications, report and block, other universities' schedule formats.

**Open questions for the team**

- Decided: the demo is a recorded run on a physical iPhone with Wi-Fi, online, on real Firebase data. Test widgets and the Lock Screen on that device early, since signing and App Group setup can differ by account type.
- Decided: Firebase Auth and Firestore are the live backend. Sign-in is email and password restricted to `@unc.edu`; friends are added by handle search with request and accept.
- Decided: club events go to everyone who has joined or subscribed to the club, while Friend Invites go only to friends you have added, whom you invite through the app. Club events are public and subscribers are notified once push notifications exist.
- Open: who creates and owns the Firebase project and billing account, and which plan the demo runs on.
- Open: final app name. Lock it before creating the Firebase iOS app and bundle ID.
