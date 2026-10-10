// Seeds fictional clubs, club events and (optionally) demo invites into Firestore.
// Clubs are written by this script only: client writes to clubs are denied by the rules.
//
// Usage (from firebase/):
//   npm run seed -- clubs                         # into the LOCAL emulator (start it first)
//   npm run seed -- invites --host <uid> --host-name "Pat Example" --to <uid>,<uid>
//   npm run seed -- clubs --real                  # into the REAL project (see below)
//
// Safety: with no flag this refuses to run unless FIRESTORE_EMULATOR_HOST is set, so it can
// never touch the real project by accident. `--real` writes to campussync-780a5 using
// Application Default Credentials (`gcloud auth application-default login`, or
// GOOGLE_APPLICATION_CREDENTIALS pointing at a service account key kept OUTSIDE the repo).
// Only run --real with the project owner's go-ahead.
//
// Event and invite times are relative to the moment you run it, so re-run it before a
// recording to get fresh, unexpired content. Everything here is fictional.

import { initializeApp, applicationDefault } from 'firebase-admin/app'
import { Timestamp, getFirestore } from 'firebase-admin/firestore'

const PROJECT_ID = 'campussync-780a5'

const args = process.argv.slice(2)
const command = args[0]
const flag = (name) => {
  const index = args.indexOf(`--${name}`)
  return index === -1 ? undefined : args[index + 1]
}
const real = args.includes('--real')

if (!['clubs', 'invites'].includes(command)) {
  console.error('Usage: seed.mjs clubs | invites --host <uid> --host-name <name> --to <uid,uid> [--real]')
  process.exit(1)
}

if (real) {
  if (process.env.FIRESTORE_EMULATOR_HOST) {
    console.error('--real was given but FIRESTORE_EMULATOR_HOST is set. Unset it to write to the real project.')
    process.exit(1)
  }
  initializeApp({ credential: applicationDefault(), projectId: PROJECT_ID })
  console.log(`Writing to the REAL project ${PROJECT_ID}`)
} else {
  if (!process.env.FIRESTORE_EMULATOR_HOST) {
    console.error('Refusing to run: FIRESTORE_EMULATOR_HOST is not set, so this would hit the real project.')
    console.error('Start the emulator (npm run emulators) and run: FIRESTORE_EMULATOR_HOST=localhost:8080 npm run seed -- clubs')
    console.error('Or pass --real to deliberately write to the real project.')
    process.exit(1)
  }
  initializeApp({ projectId: PROJECT_ID })
  console.log(`Writing to the emulator at ${process.env.FIRESTORE_EMULATOR_HOST}`)
}

const db = getFirestore()
const now = Date.now()
const hours = (h) => Timestamp.fromMillis(now + h * 3600 * 1000)

// Same ids as SampleData.swift, so the local seed and Firestore line up.
const clubs = [
  { id: 'seed-club-robots', name: 'Blue Ridge Robotics', summary: 'Build and battle small robots every semester.', symbol: 'gearshape.2.fill', access: 'duesRequired', duesAmount: 25 },
  { id: 'seed-club-debate', name: 'Lantern Debate Society', summary: 'Weekly practice rounds and tournament prep for members.', symbol: 'bubble.left.and.bubble.right.fill', access: 'membersOnly', duesAmount: 0 },
  { id: 'seed-club-film', name: 'Night Reel Film Club', summary: 'Free screenings and discussion, everyone welcome.', symbol: 'film.fill', access: 'public', duesAmount: 0 },
  { id: 'seed-club-chess', name: 'Quad Chess Union', summary: 'Casual games and a monthly tournament.', symbol: 'crown.fill', access: 'public', duesAmount: 0 },
  { id: 'seed-club-culinary', name: 'Tidewater Culinary Circle', summary: 'Cooking nights and recipe swaps.', symbol: 'frying.pan.fill', access: 'duesRequired', duesAmount: 15 },
]

const events = [
  { id: 'seed-event-film', club: 'seed-club-film', title: 'Friday night screening', details: 'A surprise classic. Popcorn provided.', location: 'Student Union Auditorium', start: 5, access: 'public', duesAmount: 0 },
  { id: 'seed-event-robots', club: 'seed-club-robots', title: 'Build night GBM', details: 'Kickoff for the spring bot. Bring a laptop.', location: 'Sitterson Hall', start: 8, access: 'duesRequired', duesAmount: 25 },
  { id: 'seed-event-debate', club: 'seed-club-debate', title: 'Practice rounds', details: 'Members-only scrimmage, two topics.', location: 'Dey Hall', start: 22, access: 'membersOnly', duesAmount: 0 },
  { id: 'seed-event-chess', club: 'seed-club-chess', title: 'Open play and ladder', details: 'All levels. Boards provided.', location: 'The Pit', start: 27, access: 'public', duesAmount: 0 },
  { id: 'seed-event-culinary', club: 'seed-club-culinary', title: 'Pasta night', details: 'Cook together, then eat together.', location: 'Student Union Kitchen', start: 50, access: 'duesRequired', duesAmount: 15 },
]

async function seedClubs() {
  const batch = db.batch()
  for (const { id, ...club } of clubs) {
    batch.set(db.collection('clubs').doc(id), club)
  }
  for (const event of events) {
    const club = clubs.find((c) => c.id === event.club)
    batch.set(db.collection('clubs').doc(event.club).collection('events').doc(event.id), {
      title: event.title,
      details: event.details,
      location: event.location,
      startTime: hours(event.start),
      access: event.access,
      duesAmount: event.duesAmount,
      clubName: club.name,
    })
  }
  await batch.commit()
  console.log(`Seeded ${clubs.length} clubs and ${events.length} events.`)
}

// A few invites from one account to some friends, timed from now so none are expired.
async function seedInvites() {
  const host = flag('host')
  const hostName = flag('host-name')
  const to = (flag('to') ?? '').split(',').filter(Boolean)
  if (!host || !hostName || to.length === 0) {
    console.error('invites needs --host <uid> --host-name <name> --to <uid,uid>')
    process.exit(1)
  }
  const plans = [
    { title: 'Lunch at the Pit', landmark: 'thePit', category: 'food', start: 1.5, length: 1 },
    { title: 'Study session at Davis', landmark: 'davisLibrary', category: 'study', start: 4, length: 2 },
    { title: 'Pickup at Woollen', landmark: 'woollenGym', category: 'fitness', start: 6, length: 1.5 },
  ]
  const batch = db.batch()
  for (const [index, plan] of plans.entries()) {
    batch.set(db.collection('invites').doc(`seed-invite-${host.slice(0, 6)}-${index}`), {
      title: plan.title,
      landmark: plan.landmark,
      category: plan.category,
      startTime: hours(plan.start),
      expiresAt: hours(plan.start + plan.length),
      hostID: host,
      hostName,
      attendeeIDs: [host],
      recipientIDs: to,
      capacity: 8,
    })
  }
  await batch.commit()
  console.log(`Seeded ${plans.length} invites from ${hostName} to ${to.length} friend(s).`)
}

if (command === 'clubs') await seedClubs()
else await seedInvites()
