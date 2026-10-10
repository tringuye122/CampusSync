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
  doc,
  getDoc,
  serverTimestamp,
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

describe('everything else is locked', () => {
  it('denies collections that have no rules yet', async () => {
    const db = student('pat')
    await assertFails(getDoc(doc(db, 'invites', 'x')))
    await assertFails(setDoc(doc(db, 'invites', 'x'), { title: 'hi' }))
    await assertFails(setDoc(doc(db, 'schedules', 'pat'), { meetings: [] }))
  })
})
