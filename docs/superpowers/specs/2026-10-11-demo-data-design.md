# Demo data: real Firebase, demoable

Status: approved by the user. 11a (seeding script) is built and tested on the emulator, not yet run against the real project. 11b (Demo mode toggle) is built and tested.

Note: `firebase-admin` is pinned to 13.x because 14.x needs Node 22 and this machine runs Node 21.

## Goal

Show real Firebase Auth and Firestore, but make the demo repeatable: a fixed cast of fictional
friends with schedules, a clock set to a day when classes happen, and clubs and invites that are
live in Firestore and not expired at the demo moment.

## Decisions (answered by the user)

- Demo moment: **Tuesday Oct 13, 2026, 12:30 PM** (the demo user's 3 h 15 min gap, friends overlap).
- Auth on camera: **real sign-up with the real verification email** (sign-in is also shown). Risk: UNC
  mail was slow or quarantined; do the sign-up flow early and keep a recorded backup. The seed
  script can mark an account verified (a fallback, never needed on camera).
- Cast: **4 fictional friends** (Alex, Jordan, Maya, Dee) plus one fictional student with a pending
  request to the demo user (Sam), so Accept can be shown.

## Approach

1. `firebase/seed/seed.mjs demo` (Admin SDK, bypasses rules, rules unchanged): creates the cast as
   real Auth users (pre-verified), their profiles, handles, shared meeting times, friendships with
   the real test accounts (`--friend-with a@unc.edu,b@unc.edu`), the pending request, invites from the
   friends, and clubs and events. Idempotent (fixed ids). `reset-demo` removes the cast.
2. Everything is timed from `--as-of` (the demo moment), **not** the wall clock. An invite seeded
   "2 hours from now" today would already be expired when the app clock reads Tuesday.
3. Safety: emulator by default (needs the Firestore and Auth emulator hosts), `--real` only with the
   owner's go-ahead. Handles carry a `_demo` suffix, and the script aborts if a handle already
   belongs to someone else. Demo passwords are random per run, printed once, and the cast is removed
   with `reset-demo` after the demo.
4. Step 11b (built): a **Demo mode** toggle in Account, not a triple-tap. Decided with the user: a
   **local demo overlay**. ON swaps the users, schedule, invites and friends repositories onto an
   in-memory demo database (`DemoWorld`: the sample-PDF schedule, the cast, invites from them, Sam's
   pending request), sets the clock to Tue Oct 13 12:30 PM, rewrites the widget, and shows a "Demo
   mode" pill in the header. OFF drops the demo database (nothing to clean up), clears the clock
   override, and refreshes live data. The live cache is never touched. The app cannot write other
   people's data to Firestore (the rules forbid it), which is why demo friends are local; the
   seeding script from step 11a is the way to put the same cast into real Firebase.
   Stays live in demo mode: sign-in, the account, clubs and Join / Pay Dues (so run
   `seed clubs --real --as-of 2026-10-13T12:30` once so club events fall after the demo moment).
   Demo mode is remembered across launches until turned off, and sign-out turns it off.
   In demo mode the schedule-sharing toggle is disabled, and imports stay in the demo database.

## The cast at Tue 12:30 PM (the demo user is free 12:15 to 3:30)

| Student | Handle | At 12:30 | Why |
| --- | --- | --- | --- |
| Maya Patel (CS '28) | `maya_demo` | Free until 3:30, mutual | class at 3:30 |
| Alex Morgan (Math '27) | `alex_demo` | Free until 5:00 | class at 5:00 |
| Jordan Lee (Bio '29) | `jordan_demo` | In class until 1:15 | class 12:00 to 1:15 |
| Dee Carter (Econ '28) | `dee_demo` | Free until 3:00 | class at 3:00 |
| Sam Rivera (Chem '29) | `sam_demo` | pending request | not a friend yet |

All names are fictional; meeting times only, never titles (the rules enforce this).
