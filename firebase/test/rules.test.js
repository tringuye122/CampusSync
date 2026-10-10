// Firestore security rules tests. Run with `npm test` inside firebase/.
// They run against the local emulator only; nothing here touches the real project.

import { after, before, beforeEach, describe, it } from 'node:test'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'
import {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment,
} from '@firebase/rules-unit-testing'
import {
  deleteDoc,
  deleteField,
  doc,
  getDoc,
  serverTimestamp,
  Timestamp,
  setDoc,
  updateDoc,
  writeBatch,
} from 'firebase/firestore'

const here = dirname(fileURLToPath(import.meta.url))
let env

// Auth contexts. Only a verified @unc.edu account counts as a student.
const student = (uid, email = `${uid}@unc.edu`) =>
  env.authenticatedContext(uid, { email, email_verified: true }).firestore()
const unverified = (uid) =>
  env.authenticatedContext(uid, { email: `${uid}@unc.edu`, email_verified: false }).firestore()
const outsider = (uid) =>
  env.authenticatedContext(uid, { email: `${uid}@gmail.com`, email_verified: true }).firestore()
const anonymous = () => env.unauthenticatedContext().firestore()

/** The batch the app sends: claim the handle and create the profile together. */
function claim(db, uid, handle, overrides = {}) {
  const batch = writeBatch(db)
  batch.set(doc(db, 'handles', handle), { uid })
  batch.set(doc(db, 'users', uid), {
    displayName: 'Pat Example',
    handle,
    createdAt: serverTimestamp(),
    ...overrides,
  })
  return batch.commit()
}

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-campussync',
    firestore: { rules: readFileSync(join(here, '..', 'firestore.rules'), 'utf8') },
  })
})

after(async () => {
  await env.cleanup()
})

beforeEach(async () => {
  await env.clearFirestore()
})

async function seedProfile(uid, handle, displayName = 'Seed User') {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore()
    await setDoc(doc(db, 'handles', handle), { uid })
    await setDoc(doc(db, 'users', uid), { displayName, handle, createdAt: new Date() })
  })
}

describe('who counts as a student', () => {
  it('rejects signed-out users', async () => {
    await assertFails(getDoc(doc(anonymous(), 'users', 'pat')))
  })

  it('rejects unverified emails', async () => {
    await assertFails(claim(unverified('pat'), 'pat', 'pat'))
    await seedProfile('other', 'other')
    await assertFails(getDoc(doc(unverified('pat'), 'users', 'other')))
  })

  it('rejects verified non-UNC emails', async () => {
    await assertFails(claim(outsider('pat'), 'pat', 'pat'))
    await seedProfile('other', 'other')
    await assertFails(getDoc(doc(outsider('pat'), 'users', 'other')))
  })

  it('rejects look-alike domains', async () => {
    await assertFails(claim(student('pat', 'pat@unc.edu.evil.com'), 'pat', 'pat'))
    await assertFails(claim(student('pat', 'pat@notunc.edu'), 'pat', 'pat'))
  })

  it('accepts a verified @unc.edu email in any letter case', async () => {
    await assertSucceeds(claim(student('pat', 'Pat@UNC.EDU'), 'pat', 'pat'))
  })
})

describe('creating a profile', () => {
  it('lets a student claim a handle and create their profile together', async () => {
    await assertSucceeds(claim(student('pat'), 'pat', 'pat_99'))
  })

  it('refuses a profile without the matching handle claim', async () => {
    const db = student('pat')
    await assertFails(
      setDoc(doc(db, 'users', 'pat'), {
        displayName: 'Pat Example',
        handle: 'pat',
        createdAt: serverTimestamp(),
      }),
    )
  })

  it('refuses a handle claim without the matching profile', async () => {
    await assertFails(setDoc(doc(student('pat'), 'handles', 'pat'), { uid: 'pat' }))
  })

  it('keeps handles unique', async () => {
    await seedProfile('first', 'pat')
    await assertFails(claim(student('second'), 'second', 'pat'))
  })

  it('refuses claiming a handle on behalf of another uid', async () => {
    const db = student('mallory')
    const batch = writeBatch(db)
    batch.set(doc(db, 'handles', 'victim'), { uid: 'victim' })
    batch.set(doc(db, 'users', 'victim'), {
      displayName: 'Victim',
      handle: 'victim',
      createdAt: serverTimestamp(),
    })
    await assertFails(batch.commit())
  })

  it('refuses a profile whose handle belongs to someone else', async () => {
    await seedProfile('first', 'taken')
    const db = student('second')
    const batch = writeBatch(db)
    batch.set(doc(db, 'users', 'second'), {
      displayName: 'Second',
      handle: 'taken',
      createdAt: serverTimestamp(),
    })
    await assertFails(batch.commit())
  })

  it('enforces the handle format', async () => {
    await assertFails(claim(student('a'), 'a', 'ab')) // too short
    await assertFails(claim(student('b'), 'b', 'Upper')) // uppercase
    await assertFails(claim(student('c'), 'c', 'has.dot'))
    await assertFails(claim(student('d'), 'd', 'a'.repeat(21))) // too long
    await assertSucceeds(claim(student('e'), 'e', 'abc'))
    await assertSucceeds(claim(student('f'), 'f', 'a'.repeat(20)))
  })

  it('enforces the display name length', async () => {
    await assertFails(claim(student('a'), 'a', 'abc', { displayName: 'P' }))
    await assertFails(claim(student('b'), 'b', 'abd', { displayName: 'x'.repeat(41) }))
    await assertFails(claim(student('c'), 'c', 'abe', { displayName: 42 }))
  })

  it('refuses extra fields such as an email', async () => {
    await assertFails(claim(student('pat'), 'pat', 'pat', { email: 'pat@unc.edu' }))
  })

  it('refuses a made-up creation time', async () => {
    await assertFails(claim(student('pat'), 'pat', 'pat', { createdAt: new Date('2020-01-01') }))
  })

  it('refuses creating a profile under another uid', async () => {
    const db = student('mallory')
    const batch = writeBatch(db)
    batch.set(doc(db, 'handles', 'abc'), { uid: 'mallory' })
    batch.set(doc(db, 'users', 'victim'), {
      displayName: 'Mallory',
      handle: 'abc',
      createdAt: serverTimestamp(),
    })
    await assertFails(batch.commit())
  })
})

describe('profile details (major and class year)', () => {
  it('lets a new profile include a valid major and class year', async () => {
    await assertSucceeds(claim(student('pat'), 'pat', 'pat', { major: 'CS', classYear: 2028 }))
  })

  it('refuses a malformed major or class year at creation', async () => {
    await assertFails(claim(student('a1'), 'a1', 'a1x', { major: '' }))
    await assertFails(claim(student('a2'), 'a2', 'a2x', { major: 'x'.repeat(31) }))
    await assertFails(claim(student('a3'), 'a3', 'a3x', { classYear: '2028' }))
    await assertFails(claim(student('a4'), 'a4', 'a4x', { classYear: 1999 }))
    await assertFails(claim(student('a5'), 'a5', 'a5x', { nickname: 'nope' }))
  })

  it('lets you set, change and clear your own details', async () => {
    await seedProfile('pat', 'pat')
    const ref = doc(student('pat'), 'users', 'pat')
    await assertSucceeds(updateDoc(ref, { major: 'Computer Science', classYear: 2028 }))
    await assertSucceeds(updateDoc(ref, { classYear: 2027 }))
    await assertSucceeds(updateDoc(ref, { major: deleteField(), classYear: deleteField() }))
  })

  it('refuses invalid details on update, and editing someone else', async () => {
    await seedProfile('pat', 'pat')
    await assertFails(updateDoc(doc(student('pat'), 'users', 'pat'), { classYear: 3000 }))
    await assertFails(updateDoc(doc(student('pat'), 'users', 'pat'), { major: 5 }))
    await assertFails(updateDoc(doc(student('eve'), 'users', 'pat'), { major: 'Hacked' }))
  })

  it('still refuses changing the handle', async () => {
    await seedProfile('pat', 'pat')
    await assertFails(updateDoc(doc(student('pat'), 'users', 'pat'), { handle: 'pat2', major: 'CS' }))
  })
})

describe('reading and editing', () => {
  it('lets any verified student read profiles and handles', async () => {
    await seedProfile('first', 'pat')
    await assertSucceeds(getDoc(doc(student('second'), 'users', 'first')))
    await assertSucceeds(getDoc(doc(student('second'), 'handles', 'pat')))
  })

  it('lets you change your own display name', async () => {
    await seedProfile('pat', 'pat')
    await assertSucceeds(updateDoc(doc(student('pat'), 'users', 'pat'), { displayName: 'Patricia' }))
  })

  it('refuses changing your handle', async () => {
    await seedProfile('pat', 'pat')
    await assertFails(updateDoc(doc(student('pat'), 'users', 'pat'), { handle: 'pat2' }))
  })

  it('refuses editing someone else\'s profile', async () => {
    await seedProfile('first', 'pat')
    await assertFails(updateDoc(doc(student('second'), 'users', 'first'), { displayName: 'Hacked' }))
  })

  it('refuses deleting profiles and any change to handles', async () => {
    await seedProfile('pat', 'pat')
    await assertFails(deleteDoc(doc(student('pat'), 'users', 'pat')))
    await assertFails(deleteDoc(doc(student('pat'), 'handles', 'pat')))
    await assertFails(setDoc(doc(student('pat'), 'handles', 'pat'), { uid: 'someone-else' }))
  })
})

// MARK: friends

const request = (from, to, overrides = {}) => ({
  fromUID: from,
  toUID: to,
  status: 'pending',
  createdAt: serverTimestamp(),
  ...overrides,
})

async function seedRequest(from, to, status = 'pending') {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'friendRequests', `${from}_${to}`), {
      fromUID: from, toUID: to, status, createdAt: new Date(),
    })
  })
}

/** The batch the app sends when `to` accepts: answer the request, then write both friend docs. */
function accept(db, from, to) {
  const batch = writeBatch(db)
  batch.update(doc(db, 'friendRequests', `${from}_${to}`), { status: 'accepted' })
  batch.set(doc(db, 'users', from, 'friends', to), { since: serverTimestamp() })
  batch.set(doc(db, 'users', to, 'friends', from), { since: serverTimestamp() })
  return batch.commit()
}

describe('friend requests', () => {
  beforeEach(async () => {
    await seedProfile('ann', 'ann')
    await seedProfile('bob', 'bob')
  })

  it('lets a student send a request to a real account', async () => {
    await assertSucceeds(setDoc(doc(student('ann'), 'friendRequests', 'ann_bob'), request('ann', 'bob')))
  })

  it('refuses a spoofed sender', async () => {
    await assertFails(setDoc(doc(student('eve'), 'friendRequests', 'ann_bob'), request('ann', 'bob')))
    await assertFails(setDoc(doc(student('eve'), 'friendRequests', 'eve_bob'), request('ann', 'bob')))
  })

  it('refuses a request to yourself', async () => {
    await assertFails(setDoc(doc(student('ann'), 'friendRequests', 'ann_ann'), request('ann', 'ann')))
  })

  it('refuses a request to an account that does not exist', async () => {
    await assertFails(setDoc(doc(student('ann'), 'friendRequests', 'ann_ghost'), request('ann', 'ghost')))
  })

  it('refuses a request that starts out accepted, or with extra fields', async () => {
    await assertFails(setDoc(doc(student('ann'), 'friendRequests', 'ann_bob'), request('ann', 'bob', { status: 'accepted' })))
    await assertFails(setDoc(doc(student('ann'), 'friendRequests', 'ann_bob'), request('ann', 'bob', { extra: 1 })))
  })

  it('refuses a request id that does not match the pair', async () => {
    await assertFails(setDoc(doc(student('ann'), 'friendRequests', 'random'), request('ann', 'bob')))
  })

  it('refuses a duplicate request in the same direction', async () => {
    await seedRequest('ann', 'bob')
    await assertFails(setDoc(doc(student('ann'), 'friendRequests', 'ann_bob'), request('ann', 'bob')))
  })

  it('refuses unverified and non-UNC accounts', async () => {
    await assertFails(setDoc(doc(unverified('ann'), 'friendRequests', 'ann_bob'), request('ann', 'bob')))
    await assertFails(setDoc(doc(outsider('ann'), 'friendRequests', 'ann_bob'), request('ann', 'bob')))
  })

  it('shows a request only to the two people involved', async () => {
    await seedRequest('ann', 'bob')
    await assertSucceeds(getDoc(doc(student('ann'), 'friendRequests', 'ann_bob')))
    await assertSucceeds(getDoc(doc(student('bob'), 'friendRequests', 'ann_bob')))
    await assertFails(getDoc(doc(student('eve'), 'friendRequests', 'ann_bob')))
  })

  it('lets only the recipient accept or decline, and only the status', async () => {
    await seedRequest('ann', 'bob')
    await assertFails(updateDoc(doc(student('ann'), 'friendRequests', 'ann_bob'), { status: 'accepted' }))
    await assertFails(updateDoc(doc(student('eve'), 'friendRequests', 'ann_bob'), { status: 'accepted' }))
    await assertFails(updateDoc(doc(student('bob'), 'friendRequests', 'ann_bob'), { status: 'accepted', toUID: 'eve' }))
    await assertSucceeds(updateDoc(doc(student('bob'), 'friendRequests', 'ann_bob'), { status: 'declined' }))
  })

  it('does not let an answered request be answered again', async () => {
    await seedRequest('ann', 'bob', 'declined')
    await assertFails(updateDoc(doc(student('bob'), 'friendRequests', 'ann_bob'), { status: 'accepted' }))
  })

  it('lets the sender cancel, and the recipient clear only an answered request', async () => {
    await seedRequest('ann', 'bob')
    await assertFails(deleteDoc(doc(student('bob'), 'friendRequests', 'ann_bob')))
    await assertFails(deleteDoc(doc(student('eve'), 'friendRequests', 'ann_bob')))
    await assertSucceeds(deleteDoc(doc(student('ann'), 'friendRequests', 'ann_bob')))
    await seedRequest('ann', 'bob', 'accepted')
    await assertSucceeds(deleteDoc(doc(student('bob'), 'friendRequests', 'ann_bob')))
  })
})

describe('friendships', () => {
  beforeEach(async () => {
    await seedProfile('ann', 'ann')
    await seedProfile('bob', 'bob')
  })

  it('writes both sides in the accept batch', async () => {
    await seedRequest('ann', 'bob')
    await assertSucceeds(accept(student('bob'), 'ann', 'bob'))
    await assertSucceeds(getDoc(doc(student('ann'), 'users', 'ann', 'friends', 'bob')))
    await assertSucceeds(getDoc(doc(student('bob'), 'users', 'bob', 'friends', 'ann')))
  })

  it('refuses a friend doc with no accepted request', async () => {
    await assertFails(setDoc(doc(student('ann'), 'users', 'ann', 'friends', 'bob'), { since: serverTimestamp() }))
    await seedRequest('ann', 'bob')
    await assertFails(setDoc(doc(student('ann'), 'users', 'ann', 'friends', 'bob'), { since: serverTimestamp() }))
    await seedRequest('ann', 'bob', 'declined')
    await assertFails(setDoc(doc(student('bob'), 'users', 'bob', 'friends', 'ann'), { since: serverTimestamp() }))
  })

  it('refuses a stranger writing a friendship between two other people', async () => {
    await seedRequest('ann', 'bob', 'accepted')
    await assertFails(setDoc(doc(student('eve'), 'users', 'ann', 'friends', 'bob'), { since: serverTimestamp() }))
  })

  it('keeps each friends list private to its owner', async () => {
    await seedRequest('ann', 'bob')
    await accept(student('bob'), 'ann', 'bob')
    await assertFails(getDoc(doc(student('bob'), 'users', 'ann', 'friends', 'bob')))
    await assertFails(getDoc(doc(student('eve'), 'users', 'ann', 'friends', 'bob')))
  })

  it('refuses edits, and lets either person unfriend both sides', async () => {
    await seedRequest('ann', 'bob')
    await accept(student('bob'), 'ann', 'bob')
    await assertFails(updateDoc(doc(student('ann'), 'users', 'ann', 'friends', 'bob'), { since: new Date() }))
    await assertFails(deleteDoc(doc(student('eve'), 'users', 'ann', 'friends', 'bob')))
    const bob = student('bob')
    const batch = writeBatch(bob)
    batch.delete(doc(bob, 'users', 'bob', 'friends', 'ann'))
    batch.delete(doc(bob, 'users', 'ann', 'friends', 'bob'))
    await assertSucceeds(batch.commit())
  })
})

// MARK: schedules, invites, clubs

async function befriend(a, b) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore()
    await setDoc(doc(db, 'users', a, 'friends', b), { since: new Date() })
    await setDoc(doc(db, 'users', b, 'friends', a), { since: new Date() })
  })
}

const meeting = (overrides = {}) => ({
  courseCode: 'COMP 523',
  weekdays: [2, 4],
  startMinutes: 805,
  endMinutes: 880,
  building: 'Sitterson Hall',
  ...overrides,
})

describe('shared schedule', () => {
  beforeEach(async () => {
    await seedProfile('ann', 'ann')
    await seedProfile('bob', 'bob')
    await seedProfile('eve', 'eve')
    await befriend('ann', 'bob')
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'schedules', 'ann', 'meetings', 'm1'), meeting())
    })
  })

  it('lets the owner write meetings', async () => {
    await assertSucceeds(setDoc(doc(student('ann'), 'schedules', 'ann', 'meetings', 'm2'), meeting()))
  })

  it('refuses writing to someone else\'s schedule', async () => {
    await assertFails(setDoc(doc(student('bob'), 'schedules', 'ann', 'meetings', 'm2'), meeting()))
  })

  it('refuses course titles, instructors or anything beyond meeting times', async () => {
    const db = student('ann')
    await assertFails(setDoc(doc(db, 'schedules', 'ann', 'meetings', 'x'), meeting({ title: 'Software Engineering Lab' })))
    await assertFails(setDoc(doc(db, 'schedules', 'ann', 'meetings', 'x'), meeting({ instructors: ['Someone'] })))
    await assertFails(setDoc(doc(db, 'schedules', 'ann', 'meetings', 'x'), meeting({ studentID: '123' })))
  })

  it('refuses malformed times and long strings', async () => {
    const db = student('ann')
    await assertFails(setDoc(doc(db, 'schedules', 'ann', 'meetings', 'x'), meeting({ endMinutes: 800 })))
    await assertFails(setDoc(doc(db, 'schedules', 'ann', 'meetings', 'x'), meeting({ endMinutes: 1500 })))
    await assertFails(setDoc(doc(db, 'schedules', 'ann', 'meetings', 'x'), meeting({ weekdays: [] })))
    await assertFails(setDoc(doc(db, 'schedules', 'ann', 'meetings', 'x'), meeting({ building: 'x'.repeat(61) })))
  })

  it('lets the owner and accepted friends read, and no one else', async () => {
    await assertSucceeds(getDoc(doc(student('ann'), 'schedules', 'ann', 'meetings', 'm1')))
    await assertSucceeds(getDoc(doc(student('bob'), 'schedules', 'ann', 'meetings', 'm1')))
    await assertFails(getDoc(doc(student('eve'), 'schedules', 'ann', 'meetings', 'm1')))
    await assertFails(getDoc(doc(unverified('bob'), 'schedules', 'ann', 'meetings', 'm1')))
  })

  it('stops friends reading once the friendship is removed', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await deleteDoc(doc(ctx.firestore(), 'users', 'ann', 'friends', 'bob'))
    })
    await assertFails(getDoc(doc(student('bob'), 'schedules', 'ann', 'meetings', 'm1')))
  })

  it('lets only the owner delete meetings', async () => {
    await assertFails(deleteDoc(doc(student('bob'), 'schedules', 'ann', 'meetings', 'm1')))
    await assertSucceeds(deleteDoc(doc(student('ann'), 'schedules', 'ann', 'meetings', 'm1')))
  })
})

const inSeconds = (s) => Timestamp.fromMillis(Date.now() + s * 1000)
const invite = (overrides = {}) => ({
  title: 'Lunch at the Pit',
  landmark: 'thePit',
  category: 'food',
  startTime: inSeconds(3600),
  expiresAt: inSeconds(7200),
  hostID: 'ann',
  hostName: 'Ann Example',
  attendeeIDs: ['ann'],
  recipientIDs: ['bob'],
  capacity: 8,
  ...overrides,
})

async function seedInvite(id = 'i1', overrides = {}) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'invites', id), invite(overrides))
  })
}

describe('friend invites', () => {
  beforeEach(async () => {
    await seedProfile('ann', 'ann', 'Ann Example')
    await seedProfile('bob', 'bob', 'Bob Example')
    await seedProfile('eve', 'eve', 'Eve Example')
  })

  it('lets a student post an invite as themselves', async () => {
    await assertSucceeds(setDoc(doc(student('ann'), 'invites', 'i1'), invite()))
  })

  it('refuses a spoofed host or host name', async () => {
    await assertFails(setDoc(doc(student('eve'), 'invites', 'i1'), invite()))
    await assertFails(setDoc(doc(student('ann'), 'invites', 'i1'), invite({ hostName: 'Someone Else' })))
  })

  it('refuses invalid invites', async () => {
    const db = student('ann')
    await assertFails(setDoc(doc(db, 'invites', 'i1'), invite({ expiresAt: inSeconds(10) })))      // expires before it starts
    await assertFails(setDoc(doc(db, 'invites', 'i1'), invite({ capacity: 1 })))
    await assertFails(setDoc(doc(db, 'invites', 'i1'), invite({ capacity: 500 })))
    await assertFails(setDoc(doc(db, 'invites', 'i1'), invite({ recipientIDs: [] })))
    await assertFails(setDoc(doc(db, 'invites', 'i1'), invite({ recipientIDs: ['ann'] })))
    await assertFails(setDoc(doc(db, 'invites', 'i1'), invite({ landmark: 'mars' })))
    await assertFails(setDoc(doc(db, 'invites', 'i1'), invite({ title: '' })))
    await assertFails(setDoc(doc(db, 'invites', 'i1'), invite({ attendeeIDs: ['ann', 'bob'] })))   // cannot RSVP others
    await assertFails(setDoc(doc(db, 'invites', 'i1'), invite({ extra: true })))
  })

  it('shows an invite only to the host and the chosen recipients', async () => {
    await seedInvite()
    await assertSucceeds(getDoc(doc(student('ann'), 'invites', 'i1')))
    await assertSucceeds(getDoc(doc(student('bob'), 'invites', 'i1')))
    await assertFails(getDoc(doc(student('eve'), 'invites', 'i1')))
  })

  it('lets a recipient RSVP and cancel as themselves only', async () => {
    await seedInvite()
    const bob = student('bob')
    await assertSucceeds(updateDoc(doc(bob, 'invites', 'i1'), { attendeeIDs: ['ann', 'bob'] }))
    await assertSucceeds(updateDoc(doc(bob, 'invites', 'i1'), { attendeeIDs: ['ann'] }))
  })

  it('refuses RSVPing or removing someone else, and editing anything else', async () => {
    await seedInvite('i1', { attendeeIDs: ['ann', 'bob'] })
    const bob = student('bob')
    await assertFails(updateDoc(doc(bob, 'invites', 'i1'), { attendeeIDs: ['bob'] }))                // removes the host
    await assertFails(updateDoc(doc(bob, 'invites', 'i1'), { attendeeIDs: ['ann', 'bob', 'eve'] }))  // adds a stranger
    await assertFails(updateDoc(doc(bob, 'invites', 'i1'), { title: 'Hijacked' }))
    await assertFails(updateDoc(doc(bob, 'invites', 'i1'), { capacity: 99 }))
    await assertFails(updateDoc(doc(student('eve'), 'invites', 'i1'), { attendeeIDs: ['ann', 'bob', 'eve'] }))
  })

  it('enforces capacity on RSVP', async () => {
    await seedInvite('i1', { capacity: 2, attendeeIDs: ['ann', 'carl'] })
    await assertFails(updateDoc(doc(student('bob'), 'invites', 'i1'), { attendeeIDs: ['ann', 'carl', 'bob'] }))
  })

  it('lets only the host delete', async () => {
    await seedInvite()
    await assertFails(deleteDoc(doc(student('bob'), 'invites', 'i1')))
    await assertSucceeds(deleteDoc(doc(student('ann'), 'invites', 'i1')))
  })
})

async function seedClub(id, access) {
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'clubs', id), { name: id, access, duesAmount: access === 'duesRequired' ? 25 : 0 })
    await setDoc(doc(ctx.firestore(), 'clubs', id, 'events', 'e1'), { title: 'GBM' })
  })
}

describe('clubs and memberships', () => {
  beforeEach(async () => {
    await seedProfile('ann', 'ann')
    await seedClub('free', 'public')
    await seedClub('paid', 'duesRequired')
  })

  it('lets verified students read clubs and events but never write them', async () => {
    await assertSucceeds(getDoc(doc(student('ann'), 'clubs', 'free')))
    await assertSucceeds(getDoc(doc(student('ann'), 'clubs', 'free', 'events', 'e1')))
    await assertFails(getDoc(doc(outsider('ann'), 'clubs', 'free')))
    await assertFails(setDoc(doc(student('ann'), 'clubs', 'new'), { name: 'x', access: 'public' }))
    await assertFails(setDoc(doc(student('ann'), 'clubs', 'free', 'events', 'e2'), { title: 'x' }))
  })

  it('lets a student join a club and leave it', async () => {
    const db = student('ann')
    await assertSucceeds(setDoc(doc(db, 'users', 'ann', 'memberships', 'free'), { joinedAt: serverTimestamp(), duesPaid: false }))
    await assertSucceeds(deleteDoc(doc(db, 'users', 'ann', 'memberships', 'free')))
  })

  it('refuses joining a club that does not exist or for someone else', async () => {
    await assertFails(setDoc(doc(student('ann'), 'users', 'ann', 'memberships', 'ghost'), { joinedAt: serverTimestamp(), duesPaid: false }))
    await assertFails(setDoc(doc(student('eve'), 'users', 'ann', 'memberships', 'free'), { joinedAt: serverTimestamp(), duesPaid: false }))
  })

  it('records dues only on a dues club', async () => {
    const db = student('ann')
    await assertFails(setDoc(doc(db, 'users', 'ann', 'memberships', 'free'), { joinedAt: serverTimestamp(), duesPaid: true }))
    await assertSucceeds(setDoc(doc(db, 'users', 'ann', 'memberships', 'paid'), { joinedAt: serverTimestamp(), duesPaid: true }))
  })

  it('lets a member upgrade to dues paid on a dues club, but not downgrade or edit other fields', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users', 'ann', 'memberships', 'paid'), { joinedAt: new Date(), duesPaid: false })
      await setDoc(doc(ctx.firestore(), 'users', 'ann', 'memberships', 'free'), { joinedAt: new Date(), duesPaid: false })
    })
    const db = student('ann')
    await assertFails(updateDoc(doc(db, 'users', 'ann', 'memberships', 'free'), { duesPaid: true }))
    await assertFails(updateDoc(doc(db, 'users', 'ann', 'memberships', 'paid'), { joinedAt: new Date() }))
    await assertSucceeds(updateDoc(doc(db, 'users', 'ann', 'memberships', 'paid'), { duesPaid: true }))
    await assertFails(updateDoc(doc(db, 'users', 'ann', 'memberships', 'paid'), { duesPaid: false }))
  })

  it('keeps memberships private to their owner', async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await setDoc(doc(ctx.firestore(), 'users', 'ann', 'memberships', 'free'), { joinedAt: new Date(), duesPaid: false })
    })
    await assertSucceeds(getDoc(doc(student('ann'), 'users', 'ann', 'memberships', 'free')))
    await assertFails(getDoc(doc(student('eve'), 'users', 'ann', 'memberships', 'free')))
  })
})

describe('everything else is locked', () => {
  it('denies collections that have no rules yet', async () => {
    const db = student('pat')
    await assertFails(getDoc(doc(db, 'reports', 'x')))
    await assertFails(setDoc(doc(db, 'reports', 'x'), { title: 'hi' }))
    await assertFails(setDoc(doc(db, 'schedules', 'pat'), { meetings: [] }))
  })
})
