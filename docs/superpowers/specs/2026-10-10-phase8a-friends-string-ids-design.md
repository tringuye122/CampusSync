# Phase 8a: String ids and friends

Status: implemented, awaiting review. Phase 8 is split into 8a (this), 8b (schedule and invite repositories, listeners into the widget snapshot) and 8c (clubs, memberships, seeding script).

## Goal

Real signed-in students can find each other by handle, send and answer friend requests, and see a friend list that syncs between phones. The SwiftData store stays a cache and fallback. Nothing writes to the real Firebase project without the user's go-ahead.

## Decisions (approved in conversation)

1. **String ids on the models.** Every `@Model` id and id reference is a `String`: `UserProfile.friendIDs/joinedClubIDs/rsvpedInviteIDs`, `OpenInvite.hostID/attendeeIDs/recipientIDs`, `ClubEvent.clubID`, and the repository signatures. Defaults are `UUID().uuidString`. Seed data uses stable ids such as `seed-user-demo` and `seed-club-robots`. `SnapshotInvite.id` is a `String` too (a `UUID` encodes as a string, so existing snapshots still decode). This is a type change to frozen files, announced here.
2. **Cache rebuild.** SwiftData cannot migrate `UUID` to `String`. `CampusSyncApp.makeContainer()` deletes the store files and rebuilds an empty store if it fails to open, then seeding runs as usual.
3. **Friend graph, approach A.** `friendRequests/{fromUID}_{toUID}` plus `users/{uid}/friends/{friendUID}` on both sides, written in one accept batch.

## Firestore rules

- `friendRequests`: create only as yourself, to another existing account, `status == 'pending'`, server `createdAt`, exact keys, id equals `from_to` (so a duplicate in the same direction is an update, which is denied). Read by the two people named. Update by the recipient only, `pending` to `accepted` or `declined`, no other field. Delete by the sender any time, or by the recipient once answered.
- `users/{uid}/friends/{friendUID}`: read by the owner only. Create by either person only while an accepted request between them exists after the batch (`getAfter`), with `since == request.time`. No updates. Delete by either person, so unfriending clears both sides in one batch.
- Change from the design as presented in conversation: deletes are allowed for both parties, which removes the "one-sided leftover" gap noted earlier.

## App

- New value types in `Firebase/FriendModels.swift` (`FriendSummary`, `FriendRequest`, `FriendError`); `Models.swift` gets no new types.
- `FriendRepository` protocol, `FirestoreFriendRepository` (real) and `InMemoryFriendRepository` (previews and tests). Reads are scoped to the signed-in student: queries on my own `fromUID` or `toUID`, my own friends subcollection, and single `get`s of `handles/{handle}` and `users/{uid}`. No collection is ever listed.
- `FriendsViewModel` and `FriendsView` (reached from Account): handle search, incoming requests with Accept and Decline, sent requests with Cancel, friends with swipe to unfriend. Failures keep the last good lists and show an offline note.
- Not in 8a: realtime listeners. Lists load on appear and pull to refresh; listeners arrive with the snapshot writer in 8b.

## Tests

- Rules (`cd firebase && npm test`): 17 new cases, 39 total.
- Unit: `FriendTests` (in-memory repository, view model, seed ids).
- Emulator integration (`firebase/run-app-tests.sh`): two students, search, request, accept, see each other, unfriend.
