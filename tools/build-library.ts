// Compiles a score library into the app's bundled library (a build product, not committed).
//
//   npm run library [-- <library-dir>]      default: priv/library, else the examples in docs/examples
//
// A library directory holds catalog.json and one <id>.jianpu per piece:
//   { "pieces": [ { "id": "laoliuban", "title": "老六板", "category": "piece", "level": 2, "lesson": 28 } ] }
// Output: apps/ios/Dizi/Library/catalog.json and Library/scores/<id>.json.
import { existsSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { compile, type Diagnostic, type Score } from '../packages/parser/src/index.ts'

const categories = ['tones', 'etude', 'piece'] as const
type Category = (typeof categories)[number]
type Entry = { id: string; title: string; category: Category; level: 1 | 2 | 3 | 4; lesson?: number }
type Built = { entry: Entry; score: Score }
type Outcome = { built: Built[]; errors: string[]; warnings: string[] }

const root = join(import.meta.dirname, '..')
const output = join(root, 'apps/ios/Dizi/Library')
const requested = process.argv[2]
const privateLibrary = join(root, 'priv/library')

const isRecord = (value: unknown): value is Record<string, unknown> => typeof value === 'object' && value !== null
const isCategory = (value: unknown): value is Category => categories.some((category) => category === value)
const isLevel = (value: unknown): value is Entry['level'] => value === 1 || value === 2 || value === 3 || value === 4
const isCount = (value: unknown): value is number => Number.isInteger(value) && (value as number) >= 1

/** One catalog piece checked field by field: the entry, or what is wrong with it. */
const parseEntry = (value: unknown, at: string): Entry | string[] => {
  if (!isRecord(value)) return [`${at}: expected an object`]
  const { id, title, category, level, lesson } = value
  const problems = [
    ...(typeof id === 'string' && /^[a-z0-9-]+$/.test(id) ? [] : [`${at}.id: expected lowercase letters, digits, -`]),
    ...(typeof title === 'string' && title !== '' ? [] : [`${at}.title: expected text`]),
    ...(isCategory(category) ? [] : [`${at}.category: expected ${categories.join(', ')}`]),
    ...(isLevel(level) ? [] : [`${at}.level: expected 1 to 4`]),
    ...(lesson === undefined || isCount(lesson) ? [] : [`${at}.lesson: expected a lesson number`]),
  ]
  if (problems.length > 0 || typeof id !== 'string' || typeof title !== 'string') return problems
  if (!isCategory(category) || !isLevel(level)) return problems
  return { id, title, category, level, ...(isCount(lesson) ? { lesson } : {}) }
}

/** catalog.json parsed into entries, with every problem found. */
const parseCatalog = (json: unknown): { entries: Entry[]; problems: string[] } => {
  const pieces = isRecord(json) ? json.pieces : undefined
  if (!Array.isArray(pieces)) return { entries: [], problems: ['pieces: expected a list'] }
  const parsed = pieces.map((piece, index) => parseEntry(piece, `pieces[${String(index)}]`))
  const entries = parsed.filter((result): result is Entry => !Array.isArray(result))
  const ids = entries.map((entry) => entry.id)
  const duplicates = ids.filter((id, index) => ids.indexOf(id) !== index).map((id) => `id '${id}' is used twice`)
  return { entries, problems: [...parsed.flatMap((result) => (Array.isArray(result) ? result : [])), ...duplicates] }
}

const located = (file: string, diagnostic: Diagnostic): string =>
  `${file}:${String(diagnostic.position.line)}:${String(diagnostic.position.column)}: ${diagnostic.message}`

/** Every piece of a library directory compiled, with the catalog's problems and the compiler's diagnostics. */
const fromLibrary = (directory: string): Outcome => {
  const catalogFile = join(directory, 'catalog.json')
  const { entries, problems } = parseCatalog(JSON.parse(readFileSync(catalogFile, 'utf8')))
  const results = entries.map((entry) => {
    const file = join(directory, `${entry.id}.jianpu`)
    return { entry, file, result: compile(readFileSync(file, 'utf8')) }
  })
  const diagnostics = (severity: Diagnostic['severity']) =>
    results.flatMap(({ file, result }) =>
      result.diagnostics.filter((diagnostic) => diagnostic.severity === severity).map((d) => located(file, d)),
    )
  return {
    built: results.flatMap(({ entry, result }) => (result.score === null ? [] : [{ entry, score: result.score }])),
    errors: [...problems.map((problem) => `${catalogFile}: ${problem}`), ...diagnostics('error')],
    warnings: diagnostics('warning'),
  }
}

/** Without a library (a fresh clone), the compiled examples stand in so the app always has pieces. */
const fromExamples = (): Outcome => {
  const examples = join(root, 'docs/examples')
  const built = readdirSync(examples)
    .filter((name) => name.endsWith('.ir.json'))
    .map((name): Built => {
      const score = JSON.parse(readFileSync(join(examples, name), 'utf8')) as Score
      const id = name.replace('.ir.json', '')
      return { entry: { id, title: score.meta.title ?? id, category: 'piece', level: 1 }, score }
    })
  return { built, errors: [], warnings: [] }
}

const keyText = (score: Score): string => {
  const { tonic, accidental } = score.header.key
  return `1=${accidental === 'flat' ? '♭' : accidental === 'sharp' ? '♯' : ''}${tonic}`
}

const timeText = (score: Score): string => {
  const time = score.measures[0]?.time
  return time === undefined || time === 'free' ? '散板' : `${String(time.beats)}/${String(time.unit)}`
}

const directory = requested ?? (existsSync(join(privateLibrary, 'catalog.json')) ? privateLibrary : null)
const { built, errors, warnings } = directory === null ? fromExamples() : fromLibrary(directory)

for (const message of warnings) console.error(`warning: ${message}`)
if (errors.length > 0) {
  console.error(errors.join('\n'))
  process.exit(1)
}
rmSync(output, { recursive: true, force: true })
mkdirSync(join(output, 'scores'), { recursive: true })
for (const { entry, score } of built) {
  writeFileSync(join(output, 'scores', `${entry.id}.json`), `${JSON.stringify(score)}\n`)
}
const catalog = built.map(({ entry, score }) => ({ ...entry, key: keyText(score), time: timeText(score) }))
writeFileSync(join(output, 'catalog.json'), `${JSON.stringify({ pieces: catalog }, null, 2)}\n`)
console.log(`library: ${String(built.length)} pieces from ${directory ?? 'docs/examples'}`)
