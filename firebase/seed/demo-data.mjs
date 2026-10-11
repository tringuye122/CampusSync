// The fictional demo cast and the documents to write for it. Pure: no Firebase imports, so the
// plan can be tested and reviewed without touching any database. Times are minutes after
// midnight and weekdays are calendar numbers (Mon = 2 ... Fri = 6), as the app stores them.
//
// All names are fictional. Meetings hold times and a building only; the rules reject anything else.

const MON = 2, TUE = 3, WED = 4, THU = 5, FRI = 6
const hm = (h, m = 0) => h * 60 + m

export const DEMO_EMAIL_PREFIX = 'campussync.demo.'

/** The cast. `friend: false` is the student with a pending request to the demo user. */
export const cast = [
  {
    uid: 'demo-maya', name: 'Maya Patel', handle: 'maya_demo', major: 'CS', classYear: 2028, friend: true,
    meetings: [
      { courseCode: 'COMP 410', weekdays: [TUE, THU], startMinutes: hm(9, 30), endMinutes: hm(10, 45), building: 'Sitterson Hall' },
      { courseCode: 'MATH 233', weekdays: [MON, WED], startMinutes: hm(11), endMinutes: hm(12, 15), building: 'Phillips Hall' },
      { courseCode: 'STOR 435', weekdays: [TUE, THU], startMinutes: hm(15, 30), endMinutes: hm(16, 45), building: 'Hanes Hall' },
    ],
  },
  {
    uid: 'demo-alex', name: 'Alex Morgan', handle: 'alex_demo', major: 'Math', classYear: 2027, friend: true,
    meetings: [
      { courseCode: 'MATH 232', weekdays: [TUE, THU], startMinutes: hm(9), endMinutes: hm(10, 15), building: 'Phillips Hall' },
      { courseCode: 'MATH 347', weekdays: [MON, WED, FRI], startMinutes: hm(10, 10), endMinutes: hm(11), building: 'Phillips Hall' },
      { courseCode: 'PHYS 118', weekdays: [TUE, THU], startMinutes: hm(17), endMinutes: hm(18, 15), building: 'Phillips Hall' },
    ],
  },
  {
    uid: 'demo-jordan', name: 'Jordan Lee', handle: 'jordan_demo', major: 'Bio', classYear: 2029, friend: true,
    meetings: [
      { courseCode: 'CHEM 101', weekdays: [MON, WED], startMinutes: hm(8), endMinutes: hm(9, 15), building: 'Venable Hall' },
      { courseCode: 'BIOL 101', weekdays: [TUE, THU], startMinutes: hm(12), endMinutes: hm(13, 15), building: 'Coker Hall' },
      { courseCode: 'BIOL 205', weekdays: [MON, WED], startMinutes: hm(14), endMinutes: hm(15, 15), building: 'Coker Hall' },
    ],
  },
  {
    uid: 'demo-dee', name: 'Dee Carter', handle: 'dee_demo', major: 'Econ', classYear: 2028, friend: true,
    meetings: [
      { courseCode: 'ECON 101', weekdays: [TUE, THU], startMinutes: hm(9), endMinutes: hm(10, 15), building: 'Gardner Hall' },
      { courseCode: 'STOR 155', weekdays: [MON, WED, FRI], startMinutes: hm(11, 15), endMinutes: hm(12, 5), building: 'Hanes Hall' },
      { courseCode: 'ECON 310', weekdays: [TUE, THU], startMinutes: hm(15), endMinutes: hm(16, 15), building: 'Gardner Hall' },
    ],
  },
  {
    uid: 'demo-sam', name: 'Sam Rivera', handle: 'sam_demo', major: 'Chem', classYear: 2029, friend: false,
    meetings: [
      { courseCode: 'CHEM 261', weekdays: [TUE, THU], startMinutes: hm(10), endMinutes: hm(11, 15), building: 'Venable Hall' },
    ],
  },
]

export const emailFor = (person) => `${DEMO_EMAIL_PREFIX}${person.handle.replace('_demo', '')}@unc.edu`

/** Friend invites, timed from the demo moment so none are expired when the app clock reads it. */
const invitePlans = [
  { host: 'demo-maya', title: 'Quick lunch at Chase', landmark: 'chaseDiningHall', category: 'food', startsInMinutes: 30, lengthMinutes: 60 },
  { host: 'demo-dee', title: 'Coffee at the Union', landmark: 'studentUnion', category: 'social', startsInMinutes: 90, lengthMinutes: 60 },
  { host: 'demo-alex', title: 'Study session at Davis', landmark: 'davisLibrary', category: 'study', startsInMinutes: 150, lengthMinutes: 120 },
]

const minutes = (base, m) => new Date(base.getTime() + m * 60000)

/**
 * Everything to write for the cast, given the demo moment and the real accounts to befriend.
 * `realUsers` is [{ uid, name }]. Returns plain objects keyed by document path.
 */
export function buildDemoPlan({ asOf, realUsers }) {
  const docs = {}
  const set = (path, data) => { docs[path] = data }

  for (const person of cast) {
    set(`users/${person.uid}`, {
      displayName: person.name, handle: person.handle, major: person.major, classYear: person.classYear,
      createdAt: asOf,
    })
    set(`handles/${person.handle}`, { uid: person.uid })
    person.meetings.forEach((meeting, index) => set(`schedules/${person.uid}/meetings/m${index}`, meeting))

    for (const real of realUsers) {
      if (person.friend) {
        // Both sides of the friendship plus the accepted request that proves it, like the app writes.
        set(`users/${person.uid}/friends/${real.uid}`, { since: asOf })
        set(`users/${real.uid}/friends/${person.uid}`, { since: asOf })
        set(`friendRequests/${person.uid}_${real.uid}`, {
          fromUID: person.uid, toUID: real.uid, status: 'accepted', createdAt: asOf,
        })
      } else {
        set(`friendRequests/${person.uid}_${real.uid}`, {
          fromUID: person.uid, toUID: real.uid, status: 'pending', createdAt: asOf,
        })
      }
    }
  }

  for (const plan of invitePlans) {
    const host = cast.find((person) => person.uid === plan.host)
    set(`invites/demo-invite-${host.handle.replace('_demo', '')}`, {
      title: plan.title, landmark: plan.landmark, category: plan.category,
      startTime: minutes(asOf, plan.startsInMinutes),
      expiresAt: minutes(asOf, plan.startsInMinutes + plan.lengthMinutes),
      hostID: host.uid, hostName: host.name,
      attendeeIDs: [host.uid], recipientIDs: realUsers.map((real) => real.uid), capacity: 8,
    })
  }
  return docs
}

/** The demo moment from `--as-of`. Without an offset it is Eastern time (UNC), EDT until Nov 1. */
export function parseAsOf(text) {
  if (!text) return new Date()
  const hasZone = /(Z|[+-]\d{2}:?\d{2})$/.test(text)
  const date = new Date(hasZone ? text : `${text}-04:00`)
  if (Number.isNaN(date.getTime())) throw new Error(`Cannot read --as-of "${text}". Use e.g. 2026-10-13T12:30`)
  return date
}
