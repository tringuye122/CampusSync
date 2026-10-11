// The demo cast: the plan itself, and that what the seed writes works with the real rules.
// Runs against the local emulator only (npm test).

import { after, before, beforeEach, describe, it } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'
import { assertFails, assertSucceeds, initializeTestEnvironment } from '@firebase/rules-unit-testing'
import { doc, getDoc, setDoc } from 'firebase/firestore'
import { buildDemoPlan, cast, emailFor, parseAsOf } from '../seed/demo-data.mjs'

const here = dirname(fileURLToPath(import.meta.url))
const asOf = parseAsOf('2026-10-13T12:30')   // Tuesday, 12:30 PM Eastern
const real = [{ uid: 'real-tri', name: 'Tri Nguyen' }]
const plan = buildDemoPlan({ asOf, realUsers: real })
const TUESDAY = 3
const NOW_MINUTES = 12 * 60 + 30

let env
const student = (uid) => env.authenticatedContext(uid, { email: `${uid}@unc.edu`, email_verified: true }).firestore()

before(async () => {
  env = await initializeTestEnvironment({
    projectId: 'demo-campussync',
    firestore: { rules: readFileSync(join(here, '..', 'firestore.rules'), 'utf8') },
  })
})
after(async () => { await env.cleanup() })
beforeEach(async () => {
  await env.clearFirestore()
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore()
    // The real account exists with a profile, like after sign-up.
    await setDoc(doc(db, 'users', 'real-tri'), { displayName: 'Tri Nguyen', handle: 'tri', createdAt: new Date() })
    for (const [path, data] of Object.entries(plan)) await setDoc(doc(db, path), data)
  })
})

describe('the demo plan', () => {
  it('has four friends and one pending request', () => {
    const friends = Object.keys(plan).filter((p) => p.startsWith('users/real-tri/friends/'))
    assert.equal(friends.length, 4)
    const pending = Object.entries(plan).filter(([p, d]) => p.startsWith('friendRequests/') && d.status === 'pending')
    assert.equal(pending.length, 1)
    assert.equal(pending[0][1].fromUID, 'demo-sam')
  })

  it('uses suffixed handles and synthetic emails so it cannot collide with real students', () => {
    for (const person of cast) {
      assert.match(person.handle, /^[a-z0-9_]{3,20}$/)
      assert.ok(person.handle.endsWith('_demo'))
      assert.match(emailFor(person), /^campussync\.demo\.[a-z]+@unc\.edu$/)
    }
  })

  it('has every invite starting after the demo moment and expiring after it starts', () => {
    const invites = Object.entries(plan).filter(([p]) => p.startsWith('invites/'))
    assert.equal(invites.length, 3)
    for (const [, invite] of invites) {
      assert.ok(invite.startTime > asOf)
      assert.ok(invite.expiresAt > invite.startTime)
    }
  })

  it('puts Jordan in class and Maya, Alex and Dee free at Tuesday 12:30', () => {
    const inClass = (person) => person.meetings.some(
      (m) => m.weekdays.includes(TUESDAY) && m.startMinutes <= NOW_MINUTES && NOW_MINUTES < m.endMinutes)
    const byUid = Object.fromEntries(cast.map((p) => [p.uid, inClass(p)]))
    assert.deepEqual(byUid, { 'demo-maya': false, 'demo-alex': false, 'demo-jordan': true, 'demo-dee': false, 'demo-sam': false })
  })

  it('reads an --as-of without an offset as Eastern time', () => {
    assert.equal(parseAsOf('2026-10-13T12:30').toISOString(), '2026-10-13T16:30:00.000Z')
    assert.equal(parseAsOf('2026-10-13T12:30:00Z').toISOString(), '2026-10-13T12:30:00.000Z')
    assert.throws(() => parseAsOf('nonsense'))
  })
})

describe('what the seeded data does under the real rules', () => {
  it('lets the real account read a friend\'s schedule, but not the pending student\'s', async () => {
    const db = student('real-tri')
    await assertSucceeds(getDoc(doc(db, 'schedules/demo-maya/meetings/0')))
    await assertFails(getDoc(doc(db, 'schedules/demo-sam/meetings/0')))
  })

  it('lets the real account read the friends\' invites and the pending request', async () => {
    const db = student('real-tri')
    await assertSucceeds(getDoc(doc(db, 'invites/demo-invite-maya')))
    await assertSucceeds(getDoc(doc(db, 'friendRequests/demo-sam_real-tri')))
  })

  it('stores meetings in a shape the rules accept (exact keys, limits)', async () => {
    for (const person of cast) {
      const db = student(person.uid)
      for (const [index, meeting] of person.meetings.entries()) {
        await assertSucceeds(setDoc(doc(db, `schedules/${person.uid}/meetings/check-${index}`), meeting))
      }
    }
  })

  it('stores invites in a shape the rules accept when the host creates them', async () => {
    const [path, invite] = Object.entries(plan).find(([p]) => p.startsWith('invites/'))
    await assertSucceeds(setDoc(doc(student(invite.hostID), `${path}-check`), invite))
  })
})
