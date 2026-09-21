#!/usr/bin/env node
// Reads Docs/release-notes.md, the one place release notes are written.
//
//   node scripts/release.mjs validate        every section, as CI runs it
//   node scripts/release.mjs notes 1.1.0     the App Store text, byte for byte
//   node scripts/release.mjs body 1.1.0      the GitHub Release body, as Markdown
//   node scripts/release.mjs status 1.1.0    what App Store Connect says: its state, its build
//   node scripts/release.mjs send 1.1.0      put the App Store text in the version's What's New
//
// `RELEASE_NOTES=<path>` reads another copy of the notes — the release workflows check the file
// as it was at the release's commit. `status` and `send` need ASC_APP_ID, ASC_KEY_ID and
// ASC_ISSUER_ID, and the key in ASC_PRIVATE_KEY_P8 or, locally, ~/.appstoreconnect/private_keys/AuthKey_<ASC_KEY_ID>.p8.
//
// No dependencies, on purpose: this runs in CI and in the release workflows with nothing installed.

import { sign } from 'node:crypto'
import { readFileSync } from 'node:fs'
import { homedir } from 'node:os'
import { fileURLToPath } from 'node:url'

export const APP_STORE_URL = 'https://apps.apple.com/app/id6788966667'
// Absolute, because a release page cannot resolve a path into the repository the way the README does.
const BADGE_URL = 'https://raw.githubusercontent.com/kguy18/babybuddyios/main/Docs/app-store-badge.svg'
/// App Store Connect's cap on "What's New in This Version".
export const APP_STORE_LIMIT = 4000

const VERSION = /^\d+\.\d+(\.\d+)?$/
const BLOCKS = ['appstore', 'whatsnew']

/// Every `## ` section in file order, with its labelled fenced blocks. Lenient by design — it
/// reports what is there, and `validate` decides what is wrong with it.
export function sections(markdown) {
  const found = []
  let section = null
  let label = null // the open fence's info string, or null outside a fence
  let lines = []

  for (const line of markdown.split('\n')) {
    if (label !== null) {
      if (line.trimEnd() === '```') {
        // A repeated label keeps the first block, so a stray second one can't replace the text.
        if (section && !(label in section.blocks)) section.blocks[label] = lines.join('\n')
        label = null
      } else {
        lines.push(line)
      }
    } else if (line.startsWith('```')) {
      label = line.slice(3).trim()
      lines = []
    } else if (line.startsWith('##')) {
      section = { heading: line, version: line.slice(2).trim(), blocks: {} }
      found.push(section)
    }
  }
  return found
}

/// Everything wrong with the file, as readable strings. Empty means it is fine.
export function validate(markdown) {
  const errors = []
  const seen = new Set()
  const all = sections(markdown)
  if (all.length === 0) errors.push('no `## <version>` sections found')

  for (const { heading, version, blocks } of all) {
    if (!heading.startsWith('## ') || !VERSION.test(version)) {
      errors.push(`malformed heading "${heading}": expected "## <major>.<minor>[.<patch>]"`)
      continue
    }
    if (seen.has(version)) errors.push(`${version}: more than one section`)
    seen.add(version)

    for (const name of BLOCKS) {
      if (!(name in blocks)) errors.push(`${version}: no \`${name}\` block`)
      else if (blocks[name].trim() === '') errors.push(`${version}: the \`${name}\` block is empty`)
    }
    const length = [...(blocks.appstore ?? '')].length
    if (length > APP_STORE_LIMIT) {
      errors.push(`${version}: the \`appstore\` block is ${length} characters; App Store Connect allows ${APP_STORE_LIMIT}`)
    }
  }
  return errors
}

/// The `appstore` block for `version`, exactly as written. Throws rather than return text from a
/// section that would not pass `validate` — this is what gets sent to App Store Connect.
export function appStoreNotes(markdown, version) {
  const mine = validate(markdown).filter((e) => e.startsWith(`${version}:`))
  if (mine.length) throw new Error(mine.join('\n'))
  const section = sections(markdown).find((s) => s.version === version)
  if (!section) throw new Error(`${version}: no section in the release notes`)
  return section.blocks.appstore
}

/// The GitHub Release body: `#New` becomes a heading, the bullets are already Markdown, and the
/// App Store badge leads, because the release carries no build to download.
// ponytail: the store text is not escaped for Markdown. It is plain prose today; escape `*`, `_`
// and `<` here if a note ever needs them literally.
export function githubBody(notes, url = APP_STORE_URL) {
  const body = notes.replace(/^#\s*(\S.*)$/gm, '### $1')
  return `[![Download on the App Store](${BADGE_URL})](${url})\n\n${body.trim()}\n`
}

// MARK: App Store Connect

const base64url = (value) => Buffer.from(value).toString('base64url')

/// A short-lived App Store Connect token. `ieee-p1363` is the part that fails silently: Node signs
/// ECDSA as DER by default, a JWT wants the raw r‖s pair, and Apple answers the DER one with a
/// bare 401.
export function jwt({ keyId, issuerId, privateKey, now = Date.now() }) {
  const iat = Math.floor(now / 1000)
  const head = base64url(JSON.stringify({ alg: 'ES256', kid: keyId, typ: 'JWT' }))
  const claims = base64url(JSON.stringify({ iss: issuerId, iat, exp: iat + 600, aud: 'appstoreconnect-v1' }))
  const signature = sign('sha256', Buffer.from(`${head}.${claims}`), { key: privateKey, dsaEncoding: 'ieee-p1363' })
  return `${head}.${claims}.${base64url(signature)}`
}

function credentials(env = process.env) {
  const { ASC_KEY_ID: keyId, ASC_ISSUER_ID: issuerId } = env
  if (!keyId || !issuerId) throw new Error('ASC_KEY_ID and ASC_ISSUER_ID must be set')
  const privateKey = env.ASC_PRIVATE_KEY_P8 ||
    readFileSync(`${homedir()}/.appstoreconnect/private_keys/AuthKey_${keyId}.p8`, 'utf8')
  return { keyId, issuerId, privateKey }
}

async function asc(path, body) {
  const response = await fetch(`https://api.appstoreconnect.apple.com${path}`, {
    method: body ? 'PATCH' : 'GET',
    headers: { Authorization: `Bearer ${jwt(credentials())}`, 'Content-Type': 'application/json' },
    body: body && JSON.stringify(body),
  })
  // Apple's error bodies name the problem and carry no credential; the token is never printed.
  if (!response.ok) throw new Error(`App Store Connect ${response.status} for ${path}\n${await response.text()}`)
  return response.json()
}

/// The iOS App Store version's state and the build attached to it, if any.
export async function status(version, appId = process.env.ASC_APP_ID) {
  if (!appId) throw new Error('ASC_APP_ID must be set')
  const query = `filter[versionString]=${encodeURIComponent(version)}&filter[platform]=IOS`
  const { data } = await asc(`/v1/apps/${appId}/appStoreVersions?${query}`)
  if (data.length !== 1) throw new Error(`${version}: App Store Connect has ${data.length} iOS versions with that number`)
  const { data: build } = await asc(`/v1/appStoreVersions/${data[0].id}/build`)
  return { id: data[0].id, state: data[0].attributes.appVersionState, build: build?.attributes.version ?? null }
}

/// Overwrites the version's "What's New in This Version" for one locale, and nothing else: it does
/// not create the version, pick a build, or submit. Apple refuses with a 409 unless the version is
/// still editable, so there is no state check here to fall out of date.
export async function sendWhatsNew(version, whatsNew, locale = process.env.ASC_LOCALE ?? 'en-US') {
  const { id } = await status(version)
  const { data } = await asc(`/v1/appStoreVersions/${id}/appStoreVersionLocalizations?limit=200`)
  const localization = data.find((l) => l.attributes.locale === locale)
  if (!localization) throw new Error(`${version}: no ${locale} localization in App Store Connect`)
  await asc(`/v1/appStoreVersionLocalizations/${localization.id}`, {
    data: { type: 'appStoreVersionLocalizations', id: localization.id, attributes: { whatsNew } },
  })
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const [command, version] = process.argv.slice(2)
  const notesFile = process.env.RELEASE_NOTES ?? new URL('../Docs/release-notes.md', import.meta.url)
  const markdown = readFileSync(notesFile, 'utf8')
  try {
    if (command === 'validate') {
      const errors = validate(markdown)
      for (const e of errors) console.error(`::error file=Docs/release-notes.md::${e}`)
      if (errors.length) process.exit(1)
      console.log(`release notes: ${sections(markdown).length} sections, all valid`)
    } else if (command === 'notes' && version) {
      process.stdout.write(appStoreNotes(markdown, version))
    } else if (command === 'body' && version) {
      process.stdout.write(githubBody(appStoreNotes(markdown, version)))
    } else if (command === 'status' && version) {
      // `state=… build=…`, one per line, so a workflow can read it with `grep`.
      const { state, build } = await status(version)
      console.log(`state=${state}\nbuild=${build ?? ''}`)
    } else if (command === 'send' && version) {
      const notes = appStoreNotes(markdown, version)
      await sendWhatsNew(version, notes)
      console.log(`${version}: What's New updated, ${[...notes].length} characters`)
    } else {
      console.error('usage: release.mjs validate | notes <version> | body <version> | status <version> | send <version>')
      process.exit(2)
    }
  } catch (error) {
    console.error(error.message)
    process.exit(1)
  }
}
