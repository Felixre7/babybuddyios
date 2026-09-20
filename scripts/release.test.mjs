// node --test scripts/release.test.mjs
import assert from 'node:assert/strict'
import { test } from 'node:test'
import { generateKeyPairSync, verify } from 'node:crypto'
import { APP_STORE_LIMIT, appStoreNotes, githubBody, jwt, validate } from './release.mjs'

const F = '```'
const section = (version, appstore, whatsnew = '#New\n- new | A title | A body') =>
  `## ${version}\n\n${F}appstore\n${appstore}\n${F}\n\n${F}whatsnew\n${whatsnew}\n${F}\n`

const STORE = `#New
- Settings → Pending Changes shows “why” — and what to do…

#Improved
- Faster.

#Fixed
- Fixed something annoying.`

const FILE = `# Release notes

    #New
    - <icon> | <title> | <body>

${section('1.1.0', STORE)}
${section('1.0', '#Fixed\n- The first one.')}`

test('the App Store text comes out exactly as written, Unicode and all', () => {
  assert.equal(appStoreNotes(FILE, '1.1.0'), STORE)
  assert.equal(appStoreNotes(FILE, '1.0'), '#Fixed\n- The first one.')
})

test('the appstore block is chosen by its label, not its position', () => {
  const swapped = `## 2.0\n\n${F}whatsnew\n#New\n- new | Card | Copy\n${F}\n\n${F}appstore\n#New\n- Store.\n${F}\n`
  assert.equal(appStoreNotes(swapped, '2.0'), '#New\n- Store.')
  assert.deepEqual(validate(swapped), [])
})

test('the GitHub body turns labels into headings and leads with the App Store link', () => {
  assert.equal(githubBody(STORE, 'https://example.com/app'), `**[Get it on the App Store](https://example.com/app)**

### New
- Settings → Pending Changes shows “why” — and what to do…

### Improved
- Faster.

### Fixed
- Fixed something annoying.
`)
})

test('a valid file has no errors', () => {
  assert.deepEqual(validate(FILE), [])
})

test('a missing version is refused', () => {
  assert.throws(() => appStoreNotes(FILE, '9.9'), /9\.9: no section/)
})

test('a section missing either block is refused', () => {
  const noCard = `## 1.2\n\n${F}appstore\n#New\n- Store.\n${F}\n`
  assert.deepEqual(validate(noCard), ['1.2: no `whatsnew` block'])
  const unlabelled = `## 1.2\n\n${F}\n#New\n- Store.\n${F}\n`
  assert.deepEqual(validate(unlabelled), ['1.2: no `appstore` block', '1.2: no `whatsnew` block'])
  assert.throws(() => appStoreNotes(unlabelled, '1.2'), /no `appstore` block/)
})

test('an empty block is refused', () => {
  assert.deepEqual(validate(section('1.2', '  ')), ['1.2: the `appstore` block is empty'])
  assert.throws(() => appStoreNotes(section('1.2', ''), '1.2'), /empty/)
})

test('malformed headings are refused', () => {
  for (const heading of ['## v1.2', '##1.2', '## 1.2 beta', '### 1.2', '## 1']) {
    const errors = validate(section('1.2', 'x').replace('## 1.2', heading))
    assert.match(errors[0], /malformed heading/, heading)
  }
})

test('a duplicated version is refused', () => {
  assert.deepEqual(validate(section('1.2', 'x') + section('1.2', 'y')), ['1.2: more than one section'])
})

test("App Store Connect's 4,000-character limit is enforced, in characters not bytes", () => {
  assert.deepEqual(validate(section('1.2', '→'.repeat(APP_STORE_LIMIT))), [])
  assert.match(validate(section('1.2', '→'.repeat(APP_STORE_LIMIT + 1)))[0], /4001 characters/)
})

test('a heading inside a fence is text, not a section', () => {
  assert.equal(appStoreNotes(section('1.2', '#New\n## not a version'), '1.2'), '#New\n## not a version')
})

test('the App Store Connect token is ES256 with a raw, not DER, signature', () => {
  const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'P-256' })
  const pem = privateKey.export({ type: 'pkcs8', format: 'pem' })
  const [head, claims, signature] = jwt({ keyId: 'KEY', issuerId: 'ISSUER', privateKey: pem, now: 1_000_000 }).split('.')

  assert.deepEqual(JSON.parse(Buffer.from(head, 'base64url')), { alg: 'ES256', kid: 'KEY', typ: 'JWT' })
  assert.deepEqual(JSON.parse(Buffer.from(claims, 'base64url')),
    { iss: 'ISSUER', iat: 1000, exp: 1600, aud: 'appstoreconnect-v1' })
  const raw = Buffer.from(signature, 'base64url')
  assert.equal(raw.length, 64) // r‖s; a DER signature is 70-72 bytes
  assert.ok(verify('sha256', Buffer.from(`${head}.${claims}`), { key: publicKey, dsaEncoding: 'ieee-p1363' }, raw))
})
