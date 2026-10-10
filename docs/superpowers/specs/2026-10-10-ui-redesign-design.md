# Phase 10: UI redesign to the supplied designs

Status: implemented, awaiting the user's review. Designs: six PDFs from the user (Home unified scroll, Schedule, Friend Overlap, Classes with inline ratings, Invites, Clubs). This phase also absorbs the old Clubs UI phase.

## Decisions (answered by the user)

- Timelines: 8 AM to 10 PM, scrollable, opening at about 9 AM (not the design's fixed 9 AM to 7 PM, which clipped free time).
- Header: optional major and class year added to the public profile (rules updated and tested).
- Tab bar: native `TabView`, restyled (the selected pill is native on iOS 26).
- Invites chips include Social.

## Assumptions made (not asked)

- The full header appears on all five tab roots, including Invites (the Invites design used a compact one).
- Ratings are real RateMyProfessors data, credited (rule 11), so the design's "demo data" labels are not used.
- Rating colors: green at 4.0 and above, amber 3.0 to 3.9, red below 3.0; "Low count" under 5 ratings.
- "Free Tue/Thu 12:15–3:30" is the longest gap between two classes that repeats at the same time on the same days.
- "Friends free now" lists friends who are free now and share a window with me that contains now, longest remaining first.
- The Friends segment keeps "make an invite" by tapping a mutual window (the design has no explicit action).
- The Import PDF button (no longer in a toolbar) lives at the bottom of Classes and in the empty states.
- Invites are one flat list (the old Now/Today/Later sections are gone).

## Data and logic added

- `ClubEvent.endTime` (additive; cache store renamed `CampusSyncCache-v3`), written by the seeding script.
- Optional `major` and `classYear` on `users/{uid}` (rules: exact keys, string 1 to 30, int 2000 to 2100).
- Pure, tested logic: `FreeWindowSummary`, `Initials`, `DayStrip`, `FriendsFreeNow`, `ClubAvailability`, `RatingStyle`, `InviteFilter`.
- New view models: `ProfileHeaderViewModel`, `ClubsViewModel`; `HomeViewModel`, `FriendOverlapViewModel` and `ScheduleViewModel` extended.
- `AppRouter` carries the Schedule segment and a focused friend, so a Home card opens Schedule > Friends on that friend.

## Not covered by the designs (left as before)

Widget, Account and Friends screens, compose sheet, sign-in screens, and the Import review screen keep their current look.
