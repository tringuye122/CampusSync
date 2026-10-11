// Seeds fictional clubs, club events and (optionally) demo invites into Firestore.
// Clubs are written by this script only: client writes to clubs are denied by the rules.
//
// Usage (from firebase/):
//   npm run seed -- clubs                         # into the LOCAL emulator (start it first)
//   npm run seed -- invites --host <uid> --host-name "Pat Example" --to <uid>,<uid>
//   npm run seed -- clubs --real --confirm campussync-780a5
//                                                 # into the REAL project (clubs only; see below)
//   npm run seed -- demo --as-of 2026-10-13T12:30 --friend-with you@unc.edu[,other@unc.edu]
//                                                 # the demo cast: accounts, friends, schedules,
//                                                 # invites, clubs, all timed from --as-of
//   npm run seed -- reset-demo                    # remove the demo cast again
//   npm run seed -- verify --email you@unc.edu    # mark an account's email verified (fallback)
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
import { getAuth } from 'firebase-admin/auth'
import { randomBytes } from 'node:crypto'
import { buildDemoPlan, cast, emailFor, parseAsOf } from './demo-data.mjs'

const PROJECT_ID = 'campussync-780a5'

const args = process.argv.slice(2)
const command = args[0]
const flag = (name) => {
  const index = args.indexOf(`--${name}`)
  return index === -1 ? undefined : args[index + 1]
}
const real = args.includes('--real')

const commands = ['clubs', 'invites', 'demo', 'reset-demo', 'verify']
if (!commands.includes(command)) {
  console.error('Usage: seed.mjs clubs | invites --host <uid> --host-name <name> --to <uid,uid> | demo --as-of <time> --friend-with <emails> | reset-demo | verify --email <email> [--real]')
  process.exit(1)
}
// Commands that touch accounts also need the Auth emulator when not writing to the real project.
const touchesAuth = ['demo', 'reset-demo', 'verify'].includes(command)

if (real) {
  // Only fictional clubs and events may go to the real project. The other commands create
  // verified accounts, friend them to real users or flip email verification, so they stay
  // emulator-only (the demo accounts for a recording are made through the emulator or by hand).
  if (command !== 'clubs') {
    console.error(`--real is only allowed with the clubs command. "${command}" changes accounts or friendships and must run against the emulator.`)
    process.exit(1)
  }
  // Any emulator variable would silently send some calls to the emulator and others to production.
  const emulatorVars = Object.keys(process.env).filter((name) => name.endsWith('_EMULATOR_HOST'))
  if (emulatorVars.length > 0) {
    console.error(`--real was given but ${emulatorVars.join(', ')} is set. Unset it to write to the real project.`)
    process.exit(1)
  }
  console.log(`About to write fictional clubs and events to the REAL project ${PROJECT_ID}.`)
  if (flag('confirm') !== PROJECT_ID) {
    console.error(`Re-run with --confirm ${PROJECT_ID} to proceed.`)
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
  if (touchesAuth && !process.env.FIREBASE_AUTH_EMULATOR_HOST) {
    console.error('Refusing to run: FIREBASE_AUTH_EMULATOR_HOST is not set, so account changes would hit the real project.')
    console.error('Run: FIRESTORE_EMULATOR_HOST=localhost:8080 FIREBASE_AUTH_EMULATOR_HOST=localhost:9099 npm run seed -- ' + command)
    process.exit(1)
  }
  initializeApp({ projectId: PROJECT_ID })
  console.log(`Writing to the emulator at ${process.env.FIRESTORE_EMULATOR_HOST}`)
}

const db = getFirestore()
// Content is timed from --as-of (the demo moment) when given, else from the moment you run this.
const asOf = parseAsOf(flag('as-of'))
const now = asOf.getTime()
const hours = (h) => Timestamp.fromMillis(now + h * 3600 * 1000)

// Same ids as SampleData.swift, so the local seed and Firestore line up. The club names are real
// campus clubs; the summaries, access, dues and events are placeholders.
const clubs = [
  { id: 'seed-club-ai', name: 'AI@UNC', summary: 'Talks, workshops and projects on artificial intelligence, open to everyone.', symbol: 'brain.head.profile', access: 'public', duesAmount: 0 },
  { id: 'seed-club-cssg', name: 'CS+SG', summary: 'Computer science students building projects and community together.', symbol: 'person.3.fill', access: 'membersOnly', duesAmount: 0 },
  { id: 'seed-club-robots', name: 'Rams Robotics', summary: 'Design, build and test robots as a team.', symbol: 'gearshape.2.fill', access: 'duesRequired', duesAmount: 25 },
  { id: 'seed-club-appteam', name: 'App Team', summary: 'Build and ship mobile apps with fellow students.', symbol: 'iphone', access: 'duesRequired', duesAmount: 15 },
  { id: 'seed-club-arvr', name: 'AR/VR UNC', summary: 'Explore augmented and virtual reality with demos and builds.', symbol: 'cube.fill', access: 'public', duesAmount: 0 },
]

const events = [
  { id: 'seed-event-ai', club: 'seed-club-ai', title: 'General meeting', details: 'An intro to what we are working on this semester. Pizza provided.', location: 'Sitterson Hall', start: 5, length: 2, access: 'public', duesAmount: 0 },
  { id: 'seed-event-robots', club: 'seed-club-robots', title: 'Build night', details: 'Kickoff for the next robot. Bring a laptop.', location: 'Sitterson Hall', start: 8, length: 1.5, access: 'duesRequired', duesAmount: 25 },
  { id: 'seed-event-cssg', club: 'seed-club-cssg', title: 'Study group', details: 'Members-only study session and project help.', location: 'Phillips Hall', start: 22, length: 1, access: 'membersOnly', duesAmount: 0 },
  { id: 'seed-event-arvr', club: 'seed-club-arvr', title: 'Headset demo night', details: 'Try the latest builds. All experience levels.', location: 'Davis Library', start: 27, length: 1.5, access: 'public', duesAmount: 0 },
  { id: 'seed-event-appteam', club: 'seed-club-appteam', title: 'Sprint planning', details: 'Plan the next release together.', location: 'Fred Brooks Building', start: 50, length: 2, access: 'duesRequired', duesAmount: 15 },
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
      endTime: hours(event.start + event.length),
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

// MARK: Demo cast

const auth = getAuth()

/** A random password, shown once. The demo accounts hold friend access to the real accounts. */
const password = flag('password') ?? process.env.DEMO_PASSWORD ?? randomBytes(12).toString('base64url')

async function realUsersFromEmails() {
  const emails = (flag('friend-with') ?? '').split(',').map((e) => e.trim()).filter(Boolean)
  if (emails.length === 0) {
    console.error('demo needs --friend-with <email[,email]>: the real, signed-up account(s) the demo friends befriend.')
    process.exit(1)
  }
  const users = []
  for (const email of emails) {
    const user = await auth.getUserByEmail(email).catch(() => null)
    if (!user) { console.error(`No account for ${email}. Sign up in the app first.`); process.exit(1) }
    const profile = await db.collection('users').doc(user.uid).get()
    if (!profile.exists) { console.error(`${email} has no profile yet. Finish sign-up in the app first.`); process.exit(1) }
    users.push({ uid: user.uid, name: profile.data().displayName })
  }
  return users
}

async function ensureAccount(person) {
  const email = emailFor(person)
  const existing = await auth.getUser(person.uid).catch(() => null)
  if (existing) {
    await auth.updateUser(person.uid, { password, emailVerified: true, displayName: person.name })
  } else {
    await auth.createUser({ uid: person.uid, email, password, emailVerified: true, displayName: person.name })
  }
}

async function seedDemo() {
  const realUsers = await realUsersFromEmails()
  // Never take over a handle that belongs to someone else.
  for (const person of cast) {
    const claim = await db.collection('handles').doc(person.handle).get()
    if (claim.exists && claim.data().uid !== person.uid) {
      console.error(`Handle ${person.handle} already belongs to another account. Aborting.`)
      process.exit(1)
    }
  }
  for (const person of cast) await ensureAccount(person)

  const plan = buildDemoPlan({ asOf, realUsers })
  const batch = db.batch()
  for (const [path, data] of Object.entries(plan)) batch.set(db.doc(path), data)
  await batch.commit()
  await seedClubs()

  console.log(`Demo cast ready as of ${asOf.toString()} (friends with ${realUsers.map((u) => u.name).join(', ')}).`)
  console.log(`Demo account password (shown once): ${password}`)
  console.log('Remove them after the demo with: npm run seed -- reset-demo')
}

async function resetDemo() {
  let removed = 0
  for (const person of cast) {
    const friends = await db.collection('users').doc(person.uid).collection('friends').get()
    for (const friend of friends.docs) {
      await db.collection('users').doc(friend.id).collection('friends').doc(person.uid).delete()
      await friend.ref.delete()
    }
    for (const field of ['fromUID', 'toUID']) {
      const requests = await db.collection('friendRequests').where(field, '==', person.uid).get()
      for (const request of requests.docs) await request.ref.delete()
    }
    const meetings = await db.collection('schedules').doc(person.uid).collection('meetings').get()
    for (const meeting of meetings.docs) await meeting.ref.delete()
    const invites = await db.collection('invites').where('hostID', '==', person.uid).get()
    for (const invite of invites.docs) await invite.ref.delete()
    await db.collection('handles').doc(person.handle).delete()
    await db.collection('users').doc(person.uid).delete()
    await auth.deleteUser(person.uid).catch(() => {})
    removed += 1
  }
  console.log(`Removed ${removed} demo accounts and their data. Clubs were left in place.`)
}

async function verifyEmail() {
  const email = flag('email')
  if (!email) { console.error('verify needs --email <email>'); process.exit(1) }
  const user = await auth.getUserByEmail(email)
  await auth.updateUser(user.uid, { emailVerified: true })
  console.log(`Marked ${email} as verified. In the app, tap "I've verified".`)
}

if (command === 'clubs') await seedClubs()
else if (command === 'invites') await seedInvites()
else if (command === 'demo') await seedDemo()
else if (command === 'reset-demo') await resetDemo()
else await verifyEmail()
