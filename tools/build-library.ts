// Compiles a score library into the app's bundled library (a build product, not committed).
//
//   npm run library [-- <library-dir>]      default: priv/library, else the examples in docs/examples
//
// A library directory holds catalog.json and one <id>.jianpu per piece:
//   { "pieces": [ { "id": "laoliuban", "title": "老六板", "category": "piece", "level": 2, "lesson": 28 } ] }
// Output: apps/ios/Dizi/Library/catalog.json and Library/scores/<id>.json.
import { existsSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { compile, type Score } from '../packages/parser/src/index.ts'

type Category = 'tones' | 'etude' | 'piece'
type Entry = { id: string; title: string; category: Category; level: number; lesson?: number }
type Built = { entry: Entry; score: Score }

const root = join(import.meta.dirname, '..')
const output = join(root, 'apps/ios/Dizi/Library')
const requested = process.argv[2]
const privateLibrary = join(root, 'priv/library')

/** Every piece of a library directory compiled, or the diagnostics of the pieces that fail. */
const fromLibrary = (directory: string): Built[] => {
  const catalog = JSON.parse(readFileSync(join(directory, 'catalog.json'), 'utf8')) as { pieces: Entry[] }
  const results = catalog.pieces.map((entry) => {
    const file = join(directory, `${entry.id}.jianpu`)
    return { entry, file, result: compile(readFileSync(file, 'utf8')) }
  })
  const failures = results.flatMap(({ file, result }) =>
    result.diagnostics
      .filter((diagnostic) => diagnostic.severity === 'error')
      .map((d) => `${file}:${String(d.position.line)}:${String(d.position.column)}: ${d.message}`),
  )
  if (failures.length > 0) {
    console.error(failures.join('\n'))
    process.exit(1)
  }
  return results.flatMap(({ entry, result }) => (result.score === null ? [] : [{ entry, score: result.score }]))
}

/** Without a library (a fresh clone), the compiled examples stand in so the app always has pieces. */
const fromExamples = (): Built[] => {
  const examples = join(root, 'docs/examples')
  return readdirSync(examples)
    .filter((name) => name.endsWith('.ir.json'))
    .map((name) => {
      const score = JSON.parse(readFileSync(join(examples, name), 'utf8')) as Score
      const id = name.replace('.ir.json', '')
      return { entry: { id, title: score.meta.title ?? id, category: 'piece', level: 1 }, score }
    })
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
const built = directory === null ? fromExamples() : fromLibrary(directory)

rmSync(output, { recursive: true, force: true })
mkdirSync(join(output, 'scores'), { recursive: true })
for (const { entry, score } of built) {
  writeFileSync(join(output, 'scores', `${entry.id}.json`), `${JSON.stringify(score)}\n`)
}
const catalog = built.map(({ entry, score }) => ({ ...entry, key: keyText(score), time: timeText(score) }))
writeFileSync(join(output, 'catalog.json'), `${JSON.stringify({ pieces: catalog }, null, 2)}\n`)
console.log(`library: ${String(built.length)} pieces from ${directory ?? 'docs/examples'}`)
