import { error, type Diagnostic } from './diagnostic.ts'
import type { Header } from './header.ts'
import type { Beam, Dots, Event, Mark, Measure, NoteValue, PartMeasure, Score, Span, Time } from './ir.ts'
import type { Body, Written, WrittenMeasure } from './parser.ts'

export type Compiled = { score: Score; diagnostics: Diagnostic[] }

/** One written measure placed on the score's clock. */
type Placed = {
  measure: Measure
  events: Event[]
  /** Breath marks between notes, at the tick of what follows them. */
  breaths: Mark[]
  /** Each event's 减时线 count, for beaming. */
  underlines: number[]
  /** The written notes in order, with their ids, for pairing slurs. */
  slurs: { id: string; semitones: number; start: boolean; end: boolean }[]
}

/** The written body as IR: ticks, ids, values, beams, spans, and marks. */
export const compileScore = (header: Header, body: Body): Compiled => {
  const placed = place(body.measures, header.time)
  const count = placed.length
  const lengthErrors = placed.flatMap((measure, index) =>
    barLengthError(measure.measure, body.measures[index], index === 0 || index === count - 1),
  )
  const shapeErrors = body.measures
    .flatMap((measure) => measure.events)
    .flatMap((event) =>
      event.kind !== 'breath' && shape(event.underlines, event.dots, event.kind === 'note' ? event.dashes : 0) === null
        ? [error(event.position, 'this length cannot be written as one note; use a tie (… | …) instead')]
        : [],
    )
  const parts: PartMeasure[] = placed.map((measure, index) => ({
    events: measure.events,
    beams: beams(measure, index === 0 && isShort(measure.measure)),
  }))
  const marks: Mark[] = [
    { kind: 'tempo', at: 0, beat: header.tempo.beat, bpm: header.tempo.bpm },
    ...placed.flatMap((measure, index) => measureMarks(measure.measure.start, body.measures[index])),
    ...placed.flatMap((measure) => measure.breaths),
  ]
  const breaks = body.measures.flatMap((measure, index) => (measure.lineBreakAfter && index < count - 1 ? [index] : []))
  const score: Score = {
    irVersion: 1,
    meta: {
      ...(header.title === undefined ? {} : { title: header.title }),
      ...(header.composer === undefined ? {} : { composer: header.composer }),
    },
    header: { key: header.key, ...(header.fingering === undefined ? {} : { fingering: header.fingering }) },
    ticksPerQuarter: 480,
    measures: placed.map((measure) => measure.measure),
    playOrder: placed.map((_, index) => index),
    parts: [{ id: 'solo', role: 'solo', measures: parts }],
    spans: spans(placed.flatMap((measure) => measure.slurs)),
    marks: marks.toSorted((a, b) => a.at - b.at),
    ...(breaks.length > 0 ? { layoutHints: { lineBreaksAfter: breaks } } : {}),
  }
  return { score, diagnostics: [...shapeErrors, ...lengthErrors] }
}

/** Written length → note value and dots; nil when no single value writes it (the parser reports those). */
export const shape = (underlines: number, dots: number, dashes: number): { value: NoteValue; dots: Dots } | null => {
  if (dashes === 0) {
    const value = 4 * 2 ** underlines
    return value <= 64 && dots <= 2 ? { value: value as NoteValue, dots: dots as Dots } : null
  }
  const withDashes: Record<number, { value: NoteValue; dots: Dots }> = {
    1: { value: 2, dots: 0 },
    2: { value: 2, dots: 1 },
    3: { value: 1, dots: 0 },
  }
  return withDashes[dashes] ?? null
}

export const ticks = (value: NoteValue, dots: Dots): number => (1920 / value) * (2 - 1 / 2 ** dots)

const fullLength = (time: Time): number | null => (time === 'free' ? null : (time.beats * 1920) / time.unit)

const place = (measures: WrittenMeasure[], initial: Time): Placed[] =>
  measures.reduce<{ placed: Placed[]; start: number; time: Time; nextId: number }>(
    (state, written, index) => {
      const time = written.changes.time ?? state.time
      const laid = layEvents(written.events, state.start, state.nextId)
      const duration = laid.end - state.start
      const measure: Measure = { index, start: state.start, duration, time, barline: written.barline }
      return {
        placed: [...state.placed, { ...laid.placed, measure }],
        start: laid.end,
        time,
        nextId: laid.nextId,
      }
    },
    { placed: [], start: 0, time: initial, nextId: 1 },
  ).placed

const layEvents = (written: Written[], start: number, firstId: number) =>
  written.reduce<{ placed: Omit<Placed, 'measure'>; end: number; nextId: number }>(
    (state, event) => {
      if (event.kind === 'breath') {
        const breath: Mark = { kind: 'breath', at: state.end, style: event.circular ? 'circular' : 'normal' }
        return { ...state, placed: { ...state.placed, breaths: [...state.placed.breaths, breath] } }
      }
      // An unwritable length is reported by compileScore; a quarter keeps the rest of the score checkable.
      const length = shape(event.underlines, event.dots, event.kind === 'note' ? event.dashes : 0) ?? {
        value: 4,
        dots: 0,
      }
      const id = `n${String(state.nextId)}`
      const duration = ticks(length.value, length.dots)
      const base = { id, start: state.end, duration, value: length.value, dots: length.dots }
      const techniques = event.techniques.length > 0 ? { techniques: event.techniques } : {}
      const placedEvent: Event =
        event.kind === 'note'
          ? {
              kind: 'note',
              ...base,
              pitch: event.pitch,
              ...techniques,
              ...(event.graces.length > 0 ? { graces: event.graces } : {}),
            }
          : { kind: 'rest', ...base, ...techniques }
      const slurs =
        event.kind === 'note'
          ? [{ id, semitones: event.pitch.semitones, start: event.slurStart, end: event.slurEnd }]
          : []
      return {
        placed: {
          ...state.placed,
          events: [...state.placed.events, placedEvent],
          underlines: [...state.placed.underlines, event.underlines],
          slurs: [...state.placed.slurs, ...slurs],
        },
        end: state.end + duration,
        nextId: state.nextId + 1,
      }
    },
    { placed: { events: [], breaths: [], underlines: [], slurs: [] }, end: start, nextId: firstId },
  )

/** Every measure must fill its bar; the first (pickup) and the last may be shorter; 散板 is not checked. */
const barLengthError = (measure: Measure, written: WrittenMeasure | undefined, mayBeShort: boolean): Diagnostic[] => {
  const full = fullLength(measure.time)
  if (full === null || written === undefined) return []
  const fits = measure.duration === full || (mayBeShort && measure.duration < full)
  return fits
    ? []
    : [
        error(
          written.position,
          `measure ${String(measure.index + 1)} lasts ${quarters(measure.duration)} quarter notes; ${timeText(measure.time)} needs ${quarters(full)}`,
        ),
      ]
}

const quarters = (ticks: number): string => String(ticks / 480)
const timeText = (time: Time): string => (time === 'free' ? 'free' : `${String(time.beats)}/${String(time.unit)}`)

/** A measure shorter than its bar: a pickup when it is the first one. */
const isShort = (measure: Measure): boolean => {
  const full = fullLength(measure.time)
  return full !== null && measure.duration < full
}

/**
 * 减时线 groups: per level, consecutive events with at least that many lines in the same beat. A beat is a
 * dotted quarter in compound time (6/8, 9/8, 12/8), else a quarter; a pickup's beats count back from its end.
 */
const beams = (measure: Placed, pickup: boolean): Beam[] => {
  const { time, start, duration } = measure.measure
  const compound = time !== 'free' && time.unit === 8 && time.beats % 3 === 0
  const beat = compound ? 720 : 480
  const full = fullLength(time) ?? duration
  const origin = pickup ? start + duration - full : start
  const deepest = Math.max(0, ...measure.underlines)
  return Array.from({ length: deepest }, (_, depth) => depth + 1).flatMap((level) => {
    const runs = measure.events.reduce<{ id: string; beat: number }[][]>((groups, event, index) => {
      if ((measure.underlines[index] ?? 0) < level) return [...groups, []]
      const entry = { id: event.id, beat: Math.floor((event.start - origin) / beat) }
      const current = groups.at(-1)
      return current !== undefined && current.at(-1)?.beat === entry.beat
        ? [...groups.slice(0, -1), [...current, entry]]
        : [...groups, [entry]]
    }, [])
    return runs.flatMap((run) => {
      const first = run[0]
      const last = run.at(-1)
      return run.length > 1 && first !== undefined && last !== undefined ? [{ level, from: first.id, to: last.id }] : []
    })
  })
}

/** `(…)` pairs; exactly two notes of the same pitch are a tie. */
const spans = (notes: Placed['slurs']): Span[] =>
  notes.reduce<{ spans: Span[]; open: number | null }>(
    (state, note, index) => {
      const opened = note.start ? index : state.open
      if (!note.end || opened === null) return { ...state, open: opened }
      const first = notes[opened]
      if (first === undefined) return { ...state, open: null }
      const tie = index - opened === 1 && first.semitones === note.semitones
      return { spans: [...state.spans, { type: tie ? 'tie' : 'slur', from: first.id, to: note.id }], open: null }
    },
    { spans: [], open: null },
  ).spans

const measureMarks = (at: number, written: WrittenMeasure | undefined): Mark[] => {
  const changes = written?.changes ?? {}
  return [
    ...(changes.section === undefined ? [] : [{ kind: 'section' as const, at, label: changes.section }]),
    ...(changes.tempo === undefined ? [] : [{ kind: 'tempo' as const, at, ...changes.tempo }]),
    ...(changes.key === undefined ? [] : [{ kind: 'keyChange' as const, at, key: changes.key }]),
  ]
}
