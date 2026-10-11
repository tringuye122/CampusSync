# CampusSync

CampusSync is a native iOS app for UNC Chapel Hill students. It shows when you and your friends are free, what is happening on campus, and puts the answer on your Home Screen and Lock Screen. It was built for HackNC by a team of two: Tri Nguyen and Justin Nguyen.

Students sign in with a verified `@unc.edu` email, import their class schedule, add friends by handle, and see who is free right now. They can post plans to friends, join clubs and see which club events fit their timetable, all kept in sync between phones.

## What it does

- **Home.** A "Free now" hero showing how long you are free and what is next, a collapsible Today card, a row of friends with a status each (mutual free window, free, in class, or no schedule shared), and a carousel of active invites.
- **Schedule.** Three views: a Timetable (one day at a time, with free gaps drawn as dotted blocks), Friends (your schedule beside a friend's, with mutual free time outlined), and Classes (your courses with RateMyProfessors ratings). Friends are added and removed here.
- **Invites.** Post a plan (food, study, fitness or social) to the friends you pick. Friends RSVP, and invites expire on their own.
- **Clubs.** Upcoming club events, each marked as fitting your schedule or conflicting with a class. Join or leave a club, pay dues (a recorded flag, never real money), and post events for clubs you have joined.
- **Widgets.** Small, medium and large Home Screen widgets, plus Lock Screen widgets. They read only a snapshot the app writes, so they work without network access.
- **Schedule import.** Import a ConnectCarolina class-schedule PDF, review it, and save. There is a demo schedule as a fallback.
- **Demo mode.** A toggle in Account that swaps in fictional friends, schedules and invites and pins the clock to a class day, without touching real data. A Reset button clears the activity you created while trying the app.

## System architecture

```
 iPhone                                                        Firebase
┌─────────────────────────────────────────────────┐      ┌──────────────────────────┐
│  SwiftUI Views                                  │      │  Authentication          │
│       │                                         │      │  (email + password,      │
│  ViewModels  (@Observable, value copies only)   │      │   @unc.edu, verified)    │
│       │                                         │      ├──────────────────────────┤
│  Repository protocols                           │      │  Cloud Firestore         │
│    User · Schedule · Invite · Club · Friend     │      │   users, handles         │
│       │                    │                    │      │   friendRequests         │
│  Local repositories   Firestore repositories ───┼─────▶│   friends, schedules     │
│       │                    ▲                    │      │   invites, clubs         │
│  SwiftData cache           │                    │      │   memberships            │
│       ▲                    │                    │      ├──────────────────────────┤
│       └──── SyncCoordinator (snapshot listeners)◀─────┤  Security rules          │
│                                                 │      └──────────────────────────┘
│  AppServices ──▶ WidgetSnapshot (JSON) ──▶ App Group ──▶ Widget extension
└─────────────────────────────────────────────────┘
```

**Layers.** Views talk to ViewModels, ViewModels talk to repository protocols, and repositories talk to storage. Views and ViewModels never touch SwiftData or Firestore directly, which is what lets the same screens run on live data, local preview data, or the in-memory demo world.

**Local cache and sync.** SwiftData is a cache, not the source of truth. Reads come from it, so screens load instantly and still work offline. Writes update the cache straight away and are sent to Firestore, where the offline queue holds them until the connection returns. A `SyncCoordinator` owns the Firestore snapshot listeners for the signed-in student (their invites, friends, memberships and the clubs) and mirrors every change into the cache. Friends' shared schedules and club events are fetched on foreground and on pull-to-refresh. View models keep plain copies of cached models, so a sync that deletes a row can never crash a screen that is still showing it.

**Backend.** Firebase Auth handles sign-up and sign-in, restricted to `@unc.edu` with email verification. Firestore holds the friend graph and shared data. Everything is protected by security rules that are tested in the Firebase emulator:

- Only verified `@unc.edu` accounts can read or write.
- Handles are unique and permanent.
- A friendship can only be created by accepting a pending request.
- A student's schedule is stored as meeting times only (day, time, building, course code), never course names, instructors or IDs, and only accepted friends can read it.
- Only the host can create an invite. Club writes are admin-only, except that club members can post and remove their own events and manage their own membership.

**Widgets.** The app writes a small versioned `WidgetSnapshot` (JSON) into a shared App Group container and reloads the widget timelines. The widget never opens the database, never links Firebase and never uses the network. Its timeline is built ahead of time with entries at each class start, class end and invite expiry.

**One clock.** Every notion of "now" goes through a single injectable `AppClock`. This is what makes demo mode (and the tests) possible: the clock can be pinned to "Tuesday, 12:30 PM".

**Demo mode.** Turning it on swaps the user, schedule, invite and friend repositories for an in-memory fictional world and pins the clock. Nothing from it is written to Firebase. Clubs and sign-in stay live. Turning it off drops the demo world and returns to live data.

## Tech stack

- Swift, SwiftUI, SwiftData, WidgetKit (iOS 17+)
- Firebase Authentication and Cloud Firestore (via Swift Package Manager)
- PDFKit (with a Vision OCR fallback) for schedule import, RateMyProfessors for ratings (cached, isolated behind a provider)
- Swift Testing for unit tests, Firebase emulator for rules and integration tests
- Node and `firebase-admin` for the seeding scripts

Every API, framework, dataset, asset and AI tool used is listed, with its role, under [Attributions](#attributions) and [AI usage](#ai-usage-disclosure) below.

## Project layout

```
CampusSync/            iOS app target
  Models/              SwiftData models, widget snapshot
  Repositories/        repository protocols and local implementations
  Firebase/            auth, Firestore repositories, sync coordinator
  ViewModels/          screen state and actions
  Views/               Home, Schedule, Invites, Clubs, Friends, Auth, shared components
  Import/              ConnectCarolina PDF parser
  Support/             theme, clock, free-time and overlap logic, widget timeline, demo world
ScheduleWidget/        widget extension
CampusSyncTests/       unit and integration tests
firebase/              Firestore rules, rules tests, seeding scripts
docs/                  spec and design notes
```

## Running it

1. Open `CampusSync/CampusSync.xcodeproj` in Xcode and run the `CampusSync` scheme on an iOS 17+ device or simulator. Widgets and the Lock Screen behave best on a physical iPhone.
2. The app needs its own Firebase project: add your `GoogleService-Info.plist` to the app target. It is not committed to the repository.
3. Security rules and their tests: `cd firebase && npm install && npm test` (runs in the local emulator).
4. App integration tests against the emulator: `firebase/run-app-tests.sh`.

## Privacy and data

The student ID in the ConnectCarolina PDF is never stored, logged or shown; only the term and courses are parsed. Real schedule PDFs, `GoogleService-Info.plist` and service account keys are never committed. Seed data is fictional apart from the club names and the demo schedule's instructors, and professor ratings come from RateMyProfessors and are credited on screen.

## Status

Built for HackNC. Accounts, friends, shared schedules, invites, clubs, widgets and demo mode are working and tested. Possible next steps: account deletion, push notifications, `.ics` import, and moving invite delivery to a per-recipient inbox so the server can verify every recipient is a friend.

## Attributions

### Apple frameworks (system SDKs, no third-party code)

| Framework | Used for |
| --- | --- |
| SwiftUI, Observation | All screens, and `@Observable` view models |
| SwiftData | The on-device cache of the signed-in student's data |
| WidgetKit | Home Screen and Lock Screen widgets |
| PDFKit | Extracting text from the ConnectCarolina schedule PDF |
| Vision | OCR fallback when a schedule PDF has no text layer (a scan) |
| UniformTypeIdentifiers, Foundation, UIKit | File picking, dates and networking, small bridges |
| Swift Testing, XCTest | Unit and UI tests |
| SF Symbols, the system font | Icons and type |

### Third-party code and services

- **Firebase iOS SDK 13.0.1** (Google, Apache License 2.0), added with Swift Package Manager. Only two products are linked: `FirebaseAuth` (email and password sign-in, email verification) and `FirebaseFirestore` (the friend graph, shared schedules, invites and clubs). Firebase's own dependencies come with it and keep their own licenses: gRPC, abseil-cpp, LevelDB, nanopb, Promises, GoogleUtilities, GoogleDataTransport, GTMSessionFetcher, App Check and the Google App Measurement and interop packages. See `CampusSync/CampusSync.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` for exact versions.
- **Firebase Authentication and Cloud Firestore** (Google), the hosted backend. Access is controlled by the rules in `firebase/firestore.rules`.
- **RateMyProfessors.com.** Professor ratings come from RateMyProfessors. It has no official public API, so the app uses the same GraphQL endpoint its website uses (`RateMyProfessorClient`). Ratings are student-submitted, are credited to RateMyProfessors on screen, are cached on the device, and fall back to "no rating" when unavailable. Their terms of use apply, and the endpoint can change or stop working without notice. No ratings are invented anywhere in the app or the seed data. We are not affiliated with RateMyProfessors.
- **Node packages for tooling only** (not shipped in the app): `firebase-tools`, `firebase-admin`, `firebase` (JS SDK), `@firebase/rules-unit-testing` and `@google-cloud/firestore`, used for the emulator, the rules tests and the seeding scripts in `firebase/`.

### Data, trademarks and design assets

- **University of North Carolina at Chapel Hill.** The UNC name, logo, seal and Old Well artwork are the property of the university. They are used here in an unofficial, non-commercial hackathon project, and CampusSync is not affiliated with or endorsed by UNC. Carolina Blue and Navy are used as the app's colors.
- **Class schedules.** Schedule import reads a student's own ConnectCarolina PDF on their device. Only the term and courses are parsed. The student ID in that PDF is never stored, logged or displayed, and real PDFs are never committed.
- **Seed and demo data is fictional,** except the five club names (AI@UNC, CS+SG, Rams Robotics, App Team, AR/VR UNC), which are real campus clubs whose summaries, dues and events here are placeholders, and the demo schedule, which uses real instructor names from a sample schedule so that real ratings can be shown.
- **Screen designs, widget designs and the app icon** were supplied by the CampusSync team. The code was written to match them.

## AI usage disclosure

This project was built with substantial help from an AI coding assistant, and we want to be clear about what that means.

**Tool.** [Claude Code](https://claude.com/claude-code), Anthropic's command-line coding agent, using Claude models. It was used by Tri and Justin throughout development, as shown by the `Co-Authored-By: Claude` trailer on the commits it helped write (`git log` shows them).

**What Claude did.**
- Wrote and edited much of the Swift app code, the widget, the Firestore security rules, the seeding scripts and the tests, working one phase at a time from the spec.
- Debugged problems we found on physical phones, from console errors we pasted in.
- Ran code reviews: it read the whole repository (security, concurrency, edge cases, accessibility) and reported issues, which we then asked it to fix.
- Wrote documentation, including this README, `CLAUDE.md` and `docs/CampusSync_Spec_Doc.md`.

**What the team did.**
- Chose the product idea, the features and every design decision, supplied the screen and widget designs and the app icon, and decided what to build next.
- Reviewed each phase, tested on physical iPhones with real Firebase data, reported what was wrong, and approved every commit and every change to the live Firebase project (rules, seed data) before it happened.
- Remain responsible for the project. AI-written code can contain mistakes, so behavior is covered by automated tests (unit tests, Firebase rules tests and emulator integration tests) and by testing on devices.

**Where AI is, and is not, in the product.**
- The app has **no AI or LLM features at runtime**. It does not call any LLM API, and no student data is sent to an AI service.
- `CLAUDE.md` in the repository root is the instruction file we gave Claude Code (project rules, design system, build order, privacy rules). It is kept so that the process is transparent.

## Credits

Built by Tri Nguyen and Justin Nguyen for HackNC, with development assistance from [Claude](https://claude.com/claude-code) (Anthropic's Claude Code).
