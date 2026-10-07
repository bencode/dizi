// Publishes the pieces marked `"publish": true` in priv/library/catalog.json to OSS (docs/library.md).
//
//   npm run publish-library -- --dry-run     what would be uploaded; no network
//   npm run publish-library                  upload (OSS_* settings from .env)
import { createHash } from 'node:crypto'
import { join } from 'node:path'
import OSS from 'ali-oss'
import { appEntry, fromLibrary, type Built } from './library.ts'

/** The bucket's public address (custom domain bound to upivot-static). */
const publicBase = 'https://g.upivot.cn'
const settings = ['OSS_REGION', 'OSS_BUCKET', 'OSS_ACCESS_KEY_ID', 'OSS_ACCESS_KEY_SECRET', 'OSS_UPLOAD_PATH'] as const

type Upload = { key: string; body: string; cacheControl: string }

const json = (value: unknown): string => `${JSON.stringify(value)}\n`
const hashName = (body: string): string => createHash('sha256').update(body).digest('hex').slice(0, 16)

/** What to upload: each piece's score, named by its content hash, and the catalog that lists them. */
const uploads = (built: Built[], prefix: string): { scores: Upload[]; catalog: Upload } => {
  const pieces = built.map((piece) => {
    const body = json(piece.score)
    return { piece, score: `scores/${hashName(body)}.json`, body }
  })
  return {
    scores: pieces.map(({ score, body }) => ({
      key: `${prefix}/${score}`,
      body,
      cacheControl: 'public, max-age=31536000, immutable',
    })),
    catalog: {
      key: `${prefix}/catalog.json`,
      body: json({ irVersion: 1, pieces: pieces.map(({ piece, score }) => ({ ...appEntry(piece), score })) }),
      cacheControl: 'public, max-age=300',
    },
  }
}

const directory = join(import.meta.dirname, '..', 'priv/library')
const { built, errors, warnings } = fromLibrary(directory)
for (const message of warnings) console.error(`warning: ${message}`)
if (errors.length > 0) {
  console.error(errors.join('\n'))
  process.exit(1)
}

const missing = settings.filter((name) => (process.env[name] ?? '') === '')
if (missing.length > 0) {
  console.error(`missing in .env: ${missing.join(', ')}`)
  process.exit(1)
}
const env = (name: (typeof settings)[number]): string => process.env[name] ?? ''
const prefix = `${env('OSS_UPLOAD_PATH').replace(/^\/+|\/+$/g, '')}/library`
const published = built.filter(({ entry }) => entry.publish === true)
const { scores, catalog } = uploads(published, prefix)

console.log(`${String(published.length)} pieces to publish, ${String(built.length - published.length)} kept private`)
published.forEach(({ entry }, index) => {
  console.log(`  ${entry.id}  ${entry.title}  ${scores[index]?.key ?? ''}`)
})
if (process.argv.includes('--dry-run')) process.exit(0)

const client = new OSS({
  region: env('OSS_REGION'),
  bucket: env('OSS_BUCKET'),
  accessKeyId: env('OSS_ACCESS_KEY_ID'),
  accessKeySecret: env('OSS_ACCESS_KEY_SECRET'),
  secure: true,
})

const exists = async (key: string): Promise<boolean> => {
  try {
    await client.head(key)
    return true
  } catch (error) {
    if (error instanceof Error && 'status' in error && error.status === 404) return false
    throw error
  }
}

const put = (upload: Upload) =>
  client.put(upload.key, Buffer.from(upload.body), {
    headers: { 'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': upload.cacheControl },
  })

// Scores first, so the catalog never lists a score that is not there yet.
for (const score of scores) {
  if (await exists(score.key)) {
    console.log(`  kept     ${score.key}`)
  } else {
    await put(score)
    console.log(`  uploaded ${score.key}`)
  }
}
await put(catalog)
console.log(`catalog: ${publicBase}/${catalog.key}`)
