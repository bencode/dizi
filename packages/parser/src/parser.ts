import { error, warning, type Diagnostic, type Position } from './diagnostic.ts'
import { parseKey, parsePitch, parseTempo, parseTime, pitch, type Tempo } from './header.ts'
import type { Barline, Grace, Key, Pitch, Technique, Time } from './ir.ts'
import type { NoteToken, RestToken, TechniqueMark, Token } from './lexer.ts'

export type WrittenNote = {
  kind: 'note'
  position: Position
  pitch: Pitch
  underlines: number
  dots: number
  dashes: number
  techniques: Technique[]
  graces: Grace[]
  slurStart: boolean
  slurEnd: boolean
}

export type WrittenRest = {
  kind: 'rest'
  position: Position
  underlines: number
  dots: number
  techniques: Technique[]
}

export type Written = WrittenNote | WrittenRest | { kind: 'breath'; circular: boolean }

export type Changes = { time?: Time; key?: Key; tempo?: Tempo; section?: string }

export type WrittenMeasure = {
  events: Written[]
  changes: Changes
  barline: Barline
  lineBreakAfter: boolean
  /** Where the closing bar line is, for diagnostics about the measure. */
  position: Position
}

export type Body = { measures: WrittenMeasure[]; diagnostics: Diagnostic[] }

type State = {
  measures: WrittenMeasure[]
  events: Written[]
  changes: Changes
  slur: { open: Position | null; startNext: boolean }
  diagnostics: Diagnostic[]
}

/** The score's measures as written, checked for structure but not yet for length. */
export const parseBody = (tokens: Token[]): Body => {
  const end = tokens.reduce(step, {
    measures: [],
    events: [],
    changes: {},
    slur: { open: null, startNext: false },
    diagnostics: [],
  })
  const last = tokens.at(-1)?.position ?? { line: 1, column: 1 }
  const unfinished = end.events.length > 0 ? [error(last, 'the score must end with a bar line')] : []
  const unclosed = end.slur.open === null ? [] : [error(end.slur.open, "a slur '(' is never closed")]
  return { measures: end.measures, diagnostics: [...end.diagnostics, ...unfinished, ...unclosed] }
}

const report = (state: State, diagnostic: Diagnostic): State => ({
  ...state,
  diagnostics: [...state.diagnostics, diagnostic],
})

const hasSound = (events: Written[]) => events.some((event) => event.kind !== 'breath')

const step = (state: State, token: Token): State => {
  const handlers: { [K in Token['kind']]: (token: Extract<Token, { kind: K }>) => State } = {
    note: (note) => addNote(state, note),
    rest: (rest) => addRest(state, rest),
    dash: (dash) => lengthen(state, dash.position),
    breath: (breath) => ({ ...state, events: [...state.events, { kind: 'breath', circular: breath.circular }] }),
    barline: (barline) => closeMeasure(state, barline.style, barline.position),
    directive: (directive) => change(state, directive.name, directive.value, directive.position),
    slurOpen: (open) =>
      state.slur.open === null
        ? { ...state, slur: { open: open.position, startNext: true } }
        : report(state, error(open.position, 'slurs cannot be nested')),
    slurClose: (close) => closeSlur(state, close.position),
    newline: (newline) => breakLine(state, newline.position),
  }
  return (handlers[token.kind] as (token: Token) => State)(token)
}

const addNote = (state: State, token: NoteToken): State => {
  const techniques = token.techniques.map(technique)
  const note: WrittenNote = {
    kind: 'note',
    position: token.position,
    pitch: pitch(token.degree, token.accidental, token.octave),
    underlines: token.underlines,
    dots: token.dots,
    dashes: 0,
    techniques: techniques.flatMap((result) => ('type' in result ? [result] : [])),
    graces: token.graces,
    slurStart: state.slur.startNext,
    slurEnd: false,
  }
  return {
    ...state,
    events: [...state.events, note],
    slur: { ...state.slur, startNext: false },
    diagnostics: [...state.diagnostics, ...techniques.flatMap((result) => ('severity' in result ? [result] : []))],
  }
}

const addRest = (state: State, token: RestToken): State => {
  const wrong = token.techniques.filter((mark) => mark.name !== 'yanchang')
  const rest: WrittenRest = {
    kind: 'rest',
    position: token.position,
    underlines: token.underlines,
    dots: token.dots,
    techniques: token.techniques.length > wrong.length ? [{ type: 'yanchang' }] : [],
  }
  const next = state.slur.startNext ? report(state, error(token.position, "a slur '(' must start on a note")) : state
  const added: State = { ...next, events: [...next.events, rest], slur: { ...next.slur, startNext: false } }
  return wrong.reduce<State>(
    (current, mark) => report(current, error(mark.position, `a rest takes only @yanchang, not @${mark.name}`)),
    added,
  )
}

/** `-` adds a beat to the quarter note before it. */
const lengthen = (state: State, position: Position): State => {
  const last = state.events.at(-1)
  if (last?.kind === 'rest') return report(state, error(position, "a rest is lengthened with more 0s, not '-'"))
  if (last?.kind !== 'note' || last.underlines > 0 || last.dots > 0) {
    return report(state, error(position, "'-' must follow a quarter note in the same measure"))
  }
  const longer = { ...last, dashes: last.dashes + 1 }
  return { ...state, events: [...state.events.slice(0, -1), longer] }
}

const closeMeasure = (state: State, style: 'single' | 'double' | 'final' | 'repeat', position: Position): State => {
  const noted =
    style === 'repeat'
      ? report(state, warning(position, 'repeats are not supported yet; the music is played once'))
      : state
  if (!hasSound(noted.events)) {
    return style === 'repeat' ? noted : report(noted, error(position, 'a measure needs at least one note or rest'))
  }
  const measure: WrittenMeasure = {
    events: noted.events,
    changes: noted.changes,
    barline: style === 'repeat' ? 'single' : style,
    lineBreakAfter: false,
    position,
  }
  return { ...noted, measures: [...noted.measures, measure], events: [], changes: {} }
}

const change = (state: State, name: string, value: string, position: Position): State => {
  if (/^\d+\.$/.test(name)) return report(state, warning(position, 'endings are not supported yet; they are ignored'))
  if (hasSound(state.events)) return report(state, error(position, `[${name} …] must start a measure`))
  const parsers: Record<string, (text: string) => Changes | null> = {
    time: (text) => mapNull(parseTime(text), (time) => ({ time })),
    key: (text) => mapNull(parseKey(text), (key) => ({ key })),
    tempo: (text) => mapNull(parseTempo(text), (tempo) => ({ tempo })),
    section: (text) => (text === '' ? null : { section: text }),
  }
  const parse = parsers[name]
  if (parse === undefined)
    return report(state, error(position, `unknown [${name} …]; expected time, key, tempo, or section`))
  const parsed = parse(value)
  return parsed === null
    ? report(state, error(position, `invalid [${name} ${value}]`))
    : { ...state, changes: { ...state.changes, ...parsed } }
}

const closeSlur = (state: State, position: Position): State => {
  const last = state.events.at(-1)
  if (state.slur.open === null) return report(state, error(position, "')' closes no slur"))
  if (last?.kind !== 'note') return report(state, error(position, "')' must follow a note"))
  return {
    ...state,
    events: [...state.events.slice(0, -1), { ...last, slurEnd: true }],
    slur: { open: null, startNext: false },
  }
}

/** A line break must follow a bar line; it records where the printed score breaks its lines. */
const breakLine = (state: State, position: Position): State => {
  if (hasSound(state.events)) return report(state, error(position, 'a line must end with a bar line'))
  const last = state.measures.at(-1)
  return last === undefined
    ? state
    : { ...state, measures: [...state.measures.slice(0, -1), { ...last, lineBreakAfter: true }] }
}

const mapNull = <T, U>(value: T | null, transform: (value: T) => U): U | null =>
  value === null ? null : transform(value)

const plain: Record<string, Technique> = {
  t: { type: 't' },
  k: { type: 'k' },
  qingtu: { type: 'qingtu' },
  baochi: { type: 'baochi' },
  qiang: { type: 'qiang' },
  feizhi: { type: 'feizhi' },
  huashe: { type: 'huashe' },
  zhizhen: { type: 'zhizhen' },
  die: { type: 'die' },
  da: { type: 'da' },
  fan: { type: 'fan' },
  bo: { type: 'bo', direction: 'up' },
  xiabo: { type: 'bo', direction: 'down' },
  rou: { type: 'rou' },
  hou: { type: 'hou' },
  fuzhen: { type: 'fuzhen' },
  qizhen: { type: 'qizhen' },
  yanchang: { type: 'yanchang' },
}

/** Techniques whose argument is a pitch; `required` ones must have it. */
const pitched: Record<string, { required: boolean; build: (pitch: Pitch | undefined) => Technique }> = {
  tr: { required: false, build: (to) => ({ type: 'tr', ...(to === undefined ? {} : { to }) }) },
  shanghua: {
    required: false,
    build: (from) => ({ type: 'slide', direction: 'up', ...(from === undefined ? {} : { from }) }),
  },
  xiahua: {
    required: false,
    build: (from) => ({ type: 'slide', direction: 'down', ...(from === undefined ? {} : { from }) }),
  },
  duo: { required: true, build: (from) => ({ type: 'duo', from: from ?? pitch(1, undefined, 0) }) },
  yuanhua: { required: true, build: (via) => ({ type: 'yuanhua', via: via ?? pitch(1, undefined, 0) }) },
}

const technique = (mark: TechniqueMark): Technique | Diagnostic => {
  const simple = plain[mark.name]
  if (simple !== undefined) {
    return mark.argument === undefined ? simple : error(mark.position, `@${mark.name} takes no argument`)
  }
  const withPitch = pitched[mark.name]
  if (withPitch === undefined) return error(mark.position, `unknown technique @${mark.name}`)
  if (mark.argument === undefined) {
    return withPitch.required
      ? error(mark.position, `@${mark.name} needs a note, such as @${mark.name}(5)`)
      : withPitch.build(undefined)
  }
  const argument = parsePitch(mark.argument)
  return argument === null
    ? error(mark.position, `invalid note '${mark.argument}' in @${mark.name}(…)`)
    : withPitch.build(argument)
}
