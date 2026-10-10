import { error, type Diagnostic, type Position } from './diagnostic.ts'
import { parsePitch, type Line } from './header.ts'
import type { Accidental, Degree, Grace } from './ir.ts'

/** A technique as written: `@tr(4)` → name `tr`, argument `4`. */
export type TechniqueMark = { name: string; argument?: string; position: Position }

export type NoteToken = {
  kind: 'note'
  position: Position
  accidental?: Accidental
  degree: Degree
  octave: number
  underlines: number
  dots: number
  techniques: TechniqueMark[]
  graces: Grace[]
}

export type RestToken = {
  kind: 'rest'
  position: Position
  underlines: number
  dots: number
  techniques: TechniqueMark[]
}

export type Token =
  | NoteToken
  | RestToken
  | { kind: 'dash'; position: Position }
  | { kind: 'breath'; position: Position; circular: boolean }
  | { kind: 'barline'; position: Position; style: BarStyle }
  | { kind: 'directive'; position: Position; name: string; value: string }
  | { kind: 'slurOpen'; position: Position }
  | { kind: 'slurClose'; position: Position }
  | { kind: 'tupletOpen'; position: Position }
  | { kind: 'tupletClose'; position: Position }
  | { kind: 'newline'; position: Position }

/** `\|:` opens a repeat, `:\|` closes one. */
export type BarStyle = 'single' | 'double' | 'final' | 'repeatStart' | 'repeatEnd'

export type Tokens = { tokens: Token[]; diagnostics: Diagnostic[] }

/** A token before graces are attached: graces stand alone until we know which note they touch. */
type Raw = { token: Token | { kind: 'grace'; position: Position; pitches: Grace['pitches'] }; spaceBefore: boolean }

type Rule = { pattern: RegExp; token: (match: RegExpExecArray, position: Position) => Raw['token'] | Diagnostic }

const noteBoundary = /^(?:[\s|){:>]|$)/

const rules: Rule[] = [
  { pattern: /^:\|\|?/, token: (_, position) => ({ kind: 'barline', position, style: 'repeatEnd' }) },
  { pattern: /^\|\|?:/, token: (_, position) => ({ kind: 'barline', position, style: 'repeatStart' }) },
  { pattern: /^\|\]/, token: (_, position) => ({ kind: 'barline', position, style: 'final' }) },
  { pattern: /^\|\|/, token: (_, position) => ({ kind: 'barline', position, style: 'double' }) },
  { pattern: /^\|/, token: (_, position) => ({ kind: 'barline', position, style: 'single' }) },
  {
    pattern: /^\[\s*([^\s\]]+)\s*([^\]]*?)\s*\]/,
    token: (match, position) => ({ kind: 'directive', position, name: match[1] ?? '', value: match[2] ?? '' }),
  },
  {
    pattern: /^\{([^}]*)\}/,
    token: (match, position) => {
      const pitches = (match[1] ?? '').match(/[#b]?[1-7](?:'+|,+)?/g) ?? []
      const parsed = pitches.map(parsePitch)
      const joined = pitches.join('')
      return parsed.some((pitch) => pitch === null) ||
        pitches.length === 0 ||
        joined !== (match[1] ?? '').replace(/\s/g, '')
        ? error(position, `invalid grace notes '{${match[1] ?? ''}}'; expected pitches such as {6} or {6'5}`)
        : { kind: 'grace', position, pitches: parsed.filter((pitch) => pitch !== null) }
    },
  },
  { pattern: /^-/, token: (_, position) => ({ kind: 'dash', position }) },
  { pattern: /^[vV]/, token: (match, position) => ({ kind: 'breath', position, circular: match[0] === 'V' }) },
  { pattern: /^\(/, token: (_, position) => ({ kind: 'slurOpen', position }) },
  { pattern: /^\)/, token: (_, position) => ({ kind: 'slurClose', position }) },
  { pattern: /^</, token: (_, position) => ({ kind: 'tupletOpen', position }) },
  { pattern: /^>/, token: (_, position) => ({ kind: 'tupletClose', position }) },
  {
    pattern: /^([#b]?)([0-7])('+|,+)?(_*)(\.*)((?:@[A-Za-z]+(?:\([^)]*\))?)*)/,
    token: (match, position) => noteOrRest(match, position),
  },
]

const noteOrRest = (match: RegExpExecArray, position: Position): Raw['token'] | Diagnostic => {
  const [text = '', accidental = '', digit = '0', octaves = '', underlines = '', dots = '', marks = ''] = match
  const techniques = [...marks.matchAll(/@([A-Za-z]+)(?:\(([^)]*)\))?/g)].map((mark): TechniqueMark => ({
    name: mark[1] ?? '',
    ...(mark[2] === undefined ? {} : { argument: mark[2] }),
    position: { line: position.line, column: position.column + text.indexOf(mark[0]) },
  }))
  if (digit === '0') {
    return accidental !== '' || octaves !== ''
      ? error(position, `a rest '0' takes no accidental or octave dots`)
      : { kind: 'rest', position, underlines: underlines.length, dots: dots.length, techniques }
  }
  return {
    kind: 'note',
    position,
    ...(accidental === '' ? {} : { accidental: accidental === '#' ? 'sharp' : 'flat' }),
    degree: Number(digit) as Degree,
    octave: octaves.startsWith("'") ? octaves.length : octaves === '' ? 0 : -octaves.length,
    underlines: underlines.length,
    dots: dots.length,
    techniques,
    graces: [],
  }
}

const isDiagnostic = (value: Raw['token'] | Diagnostic): value is Diagnostic => 'severity' in value

/** Scans one line from left to right; a bad stretch is reported and skipped up to the next space. */
const scanLine = (line: Line): { raws: Raw[]; diagnostics: Diagnostic[] } => {
  const raws: Raw[] = []
  const diagnostics: Diagnostic[] = []
  const text = line.text
  let index = 0
  let spaceBefore = true
  while (index < text.length) {
    const rest = text.slice(index)
    const space = /^\s+/.exec(rest)
    if (space !== null) {
      index += space[0].length
      spaceBefore = true
      continue
    }
    if (rest.startsWith('//')) break
    const position = { line: line.number, column: index + 1 }
    const scanned = rules
      .map((rule) => ({ rule, match: rule.pattern.exec(rest) }))
      .find(({ match }) => match !== null && match[0].length > 0)
    if (scanned === undefined || scanned.match === null) {
      diagnostics.push(error(position, `unexpected '${text.charAt(index)}'`))
      index = skipToSpace(text, index)
    } else {
      const token = scanned.rule.token(scanned.match, position)
      const end = index + scanned.match[0].length
      if (isDiagnostic(token)) {
        diagnostics.push(token)
        index = skipToSpace(text, index)
      } else if ((token.kind === 'note' || token.kind === 'rest') && !noteBoundary.test(text.slice(end))) {
        diagnostics.push(error({ line: line.number, column: end + 1 }, `unexpected '${text.charAt(end)}' after a note`))
        index = skipToSpace(text, end)
      } else {
        raws.push({ token, spaceBefore })
        index = end
      }
    }
    spaceBefore = false
  }
  return { raws, diagnostics }
}

const skipToSpace = (text: string, from: number): number => {
  const next = text.slice(from).search(/\s/)
  return next === -1 ? text.length : from + next
}

/** Grace notes touch exactly one note: `{6}5` before it, `5{6}` after it. */
const withGraces = (raws: Raw[]): { tokens: Token[]; diagnostics: Diagnostic[] } => {
  const isNote = (index: number) => raws[index]?.token.kind === 'note'
  const side = (raw: Raw, index: number): 'before' | 'after' | null => {
    const touchesPrevious = !raw.spaceBefore && isNote(index - 1)
    const touchesNext = raws[index + 1]?.spaceBefore === false && isNote(index + 1)
    return touchesPrevious === touchesNext ? null : touchesPrevious ? 'after' : 'before'
  }
  const graceFor = (index: number, position: 'before' | 'after'): Grace[] => {
    const raw = raws[index]
    return raw?.token.kind === 'grace' && side(raw, index) === position
      ? [{ position, pitches: raw.token.pitches }]
      : []
  }
  const tokens = raws.flatMap(({ token }, index): Token[] =>
    token.kind === 'grace'
      ? []
      : token.kind === 'note'
        ? [{ ...token, graces: [...graceFor(index - 1, 'before'), ...graceFor(index + 1, 'after')] }]
        : [token],
  )
  const diagnostics = raws.flatMap((raw, index) =>
    raw.token.kind === 'grace' && side(raw, index) === null
      ? [error(raw.token.position, 'grace notes must touch exactly one note')]
      : [],
  )
  return { tokens, diagnostics }
}

/** The body's tokens, with a `newline` between lines that have any (none after the last). */
export const tokenize = (lines: Line[]): Tokens => {
  const all = lines.reduce<Tokens>(
    (result, line) => {
      const scanned = scanLine(line)
      const graced = withGraces(scanned.raws)
      const newline: Token[] =
        graced.tokens.length > 0
          ? [{ kind: 'newline', position: { line: line.number, column: line.text.length + 1 } }]
          : []
      return {
        tokens: [...result.tokens, ...graced.tokens, ...newline],
        diagnostics: [...result.diagnostics, ...scanned.diagnostics, ...graced.diagnostics],
      }
    },
    { tokens: [], diagnostics: [] },
  )
  return all.tokens.at(-1)?.kind === 'newline' ? { ...all, tokens: all.tokens.slice(0, -1) } : all
}
