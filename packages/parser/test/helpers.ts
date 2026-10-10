import { compile, type Result } from '../src/index.ts'
import type { Event, Score } from '../src/ir.ts'

/** A score with a standard header; `body` is the music. */
export const score = (body: string, header = 'key: 1=D\ntime: 2/4\ntempo: 60'): Result =>
  compile(`${header}\n\n${body}\n`)

export const compiled = (body: string, header?: string): Score => {
  const result = score(body, header)
  if (result.score === null) throw new Error(result.diagnostics.map((d) => d.message).join('\n'))
  return result.score
}

export const events = (result: Score): Event[] => result.parts.flatMap((part) => part.measures.flatMap((m) => m.events))

export const errors = (body: string, header?: string): string[] =>
  score(body, header)
    .diagnostics.filter((d) => d.severity === 'error')
    .map((d) => `${String(d.position.line)}:${String(d.position.column)} ${d.message}`)
