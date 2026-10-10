import { readFileSync } from 'node:fs'
import { compile } from './index.ts'

// Usage: npm run compile -- <score.jianpu>   prints the IR JSON, or the diagnostics and exits with 1.
const [file] = process.argv.slice(2)
if (file === undefined) {
  console.error('usage: compile <score.jianpu>')
  process.exit(2)
}
const result = compile(readFileSync(file, 'utf8'))
for (const diagnostic of result.diagnostics) {
  const { line, column } = diagnostic.position
  console.error(`${file}:${String(line)}:${String(column)}: ${diagnostic.severity}: ${diagnostic.message}`)
}
if (result.score === null) process.exit(1)
process.stdout.write(`${JSON.stringify(result.score, null, 2)}\n`)
