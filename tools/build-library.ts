// Compiles a score library into the app's bundled library (a build product, not committed).
//
//   npm run library [-- <library-dir>]      default: priv/library, else the examples in docs/examples
//
// A library directory holds catalog.json and one <id>.jianpu per piece:
//   { "pieces": [ { "id": "laoliuban", "title": "老六板", "category": "piece", "level": 2, "lesson": 28 } ] }
// Output: apps/ios/Dizi/Library/, laid out like the published library (docs/library.md).
import { existsSync, mkdirSync, rmSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'
import { fromExamples, fromLibrary, listing } from './library.ts'

const root = join(import.meta.dirname, '..')
const output = join(root, 'apps/ios/Dizi/Library')
const requested = process.argv[2]
const privateLibrary = join(root, 'priv/library')

const directory = requested ?? (existsSync(join(privateLibrary, 'catalog.json')) ? privateLibrary : null)
const { built, errors, warnings } = directory === null ? fromExamples(root) : fromLibrary(directory)

for (const message of warnings) console.error(`warning: ${message}`)
if (errors.length > 0) {
  console.error(errors.join('\n'))
  process.exit(1)
}
rmSync(output, { recursive: true, force: true })
mkdirSync(join(output, 'scores'), { recursive: true })
const { scores, catalog } = listing(built, Math.floor(Date.now() / 1000))
for (const score of scores) writeFileSync(join(output, score.path), score.body)
writeFileSync(join(output, 'catalog.json'), catalog)
console.log(`library: ${String(built.length)} pieces from ${directory ?? 'docs/examples'}`)
