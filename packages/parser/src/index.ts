import { compileScore } from './compile.ts'
import { byPosition, hasErrors, type Diagnostic } from './diagnostic.ts'
import { parseHeader, type Line } from './header.ts'
import type { Score } from './ir.ts'
import { tokenize } from './lexer.ts'
import { parseBody } from './parser.ts'

export type { Diagnostic } from './diagnostic.ts'
export type * from './ir.ts'

export type Result = { score: Score | null; diagnostics: Diagnostic[] }

/** Score text → IR. Every diagnostic is reported; any error means no score. */
export const compile = (text: string): Result => {
  const lines: Line[] = text.split(/\r?\n/).map((line, index) => ({ number: index + 1, text: line }))
  const header = parseHeader(lines)
  const tokens = tokenize(lines.slice(header.bodyStart))
  const body = parseBody(tokens.tokens)
  const compiled = header.header === null ? null : compileScore(header.header, body)
  const diagnostics = [
    ...header.diagnostics,
    ...tokens.diagnostics,
    ...body.diagnostics,
    ...(compiled?.diagnostics ?? []),
  ]
  return {
    score: compiled === null || hasErrors(diagnostics) ? null : compiled.score,
    diagnostics: diagnostics.toSorted(byPosition),
  }
}
