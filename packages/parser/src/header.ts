import { error, warning, type Diagnostic } from './diagnostic.ts'
import type { Accidental, Degree, Key, Letter, Pitch, Time } from './ir.ts'

export type Line = { number: number; text: string }

export type Tempo = { beat: number; bpm: number }

export type Header = {
  title?: string
  composer?: string
  key: Key
  time: Time
  tempo: Tempo
  fingering?: { degree: Degree; octave: number }
}

export type HeaderResult = { header: Header | null; bodyStart: number; diagnostics: Diagnostic[] }

type Field = { name: string; value: string; line: Line; valueColumn: number }

const fieldPattern = /^(\s*)([a-z]+)(\s*:\s*)(.*?)\s*(?:\/\/.*)?$/
const knownFields = new Set(['title', 'composer', 'key', 'time', 'tempo', 'fingering'])
const isBlankOrComment = (line: Line): boolean => /^\s*(\/\/.*)?$/.test(line.text)

/** The leading `name: value` lines; the first other line starts the body. */
export const parseHeader = (lines: Line[]): HeaderResult => {
  const bodyStart = lines.findIndex((line) => !isBlankOrComment(line) && !fieldPattern.test(line.text))
  const headerLines = lines.slice(0, bodyStart === -1 ? lines.length : bodyStart)
  const fields = headerLines.flatMap((line): Field[] => {
    const match = fieldPattern.exec(line.text)
    if (match === null) return []
    const [, indent = '', name = '', separator = '', value = ''] = match
    return [{ name, value, line, valueColumn: indent.length + name.length + separator.length + 1 }]
  })
  const at = (field: Field) => ({ line: field.line.number, column: field.valueColumn })
  const seen = fields.map((field) => field.name)
  const fieldDiagnostics = fields.flatMap((field, index): Diagnostic[] => [
    ...(seen.indexOf(field.name) < index ? [error(at(field), `field '${field.name}' is given twice`)] : []),
    ...(knownFields.has(field.name) ? [] : [warning(at(field), `unknown field '${field.name}' is ignored`)]),
  ])
  const find = (name: string) => fields.find((field) => field.name === name)
  const required = <T>(name: string, parse: (text: string) => T | null, expected: string) => {
    const field = find(name)
    if (field === undefined)
      return { value: null, diagnostics: [error({ line: 1, column: 1 }, `missing field '${name}'`)] }
    const value = parse(field.value)
    return value === null
      ? { value, diagnostics: [error(at(field), `invalid ${name} '${field.value}'; expected ${expected}`)] }
      : { value, diagnostics: [] }
  }
  const key = required('key', parseKey, '1=<letter>, such as 1=D or 1=bB')
  const time = required('time', parseTime, '<beats>/<unit> such as 2/4, or free')
  const tempo = required('tempo', parseTempo, 'beats per minute 20-300, such as 72 or 4.=60')
  const fingeringField = find('fingering')
  const fingering = fingeringField === undefined ? null : parsePitch(fingeringField.value)
  const fingeringDiagnostics =
    fingeringField !== undefined && fingering === null
      ? [error(at(fingeringField), `invalid fingering '${fingeringField.value}'; expected a degree such as 5,`)]
      : []
  const diagnostics = [
    ...fieldDiagnostics,
    ...key.diagnostics,
    ...time.diagnostics,
    ...tempo.diagnostics,
    ...fingeringDiagnostics,
  ]
  const text = (name: string) => find(name)?.value
  const title = text('title')
  const composer = text('composer')
  const header: Header | null =
    key.value === null || time.value === null || tempo.value === null
      ? null
      : {
          ...(title === undefined ? {} : { title }),
          ...(composer === undefined ? {} : { composer }),
          key: key.value,
          time: time.value,
          tempo: tempo.value,
          ...(fingering === null ? {} : { fingering: { degree: fingering.degree, octave: fingering.octave } }),
        }
  return { header, bodyStart: bodyStart === -1 ? lines.length : bodyStart, diagnostics }
}

const accidentals: Record<string, Accidental> = { '#': 'sharp', b: 'flat' }

/** `1=D`, `1=bB`, `1=#F` */
export const parseKey = (text: string): Key | null => {
  const match = /^1=([#b]?)([A-G])$/.exec(text)
  if (match === null) return null
  const [, accidental = '', tonic = 'C'] = match
  const sign = accidentals[accidental]
  return { tonic: tonic as Letter, ...(sign === undefined ? {} : { accidental: sign }) }
}

/** `2/4`, `6/8`, `free` */
export const parseTime = (text: string): Time | null => {
  if (text === 'free') return 'free'
  const match = /^(\d+)\/(2|4|8|16)$/.exec(text)
  if (match === null) return null
  const beats = Number(match[1])
  const unit = Number(match[2]) as 2 | 4 | 8 | 16
  return beats >= 1 && beats <= 32 ? { beats, unit } : null
}

/** `72` (quarter notes), `4.=60`, `8=144` */
export const parseTempo = (text: string): Tempo | null => {
  const match = /^(?:(2|4|8)(\.?)=)?(\d+)$/.exec(text)
  if (match === null) return null
  const [, unit = '4', dot = '', bpm = ''] = match
  const beat = (1920 / Number(unit)) * (dot === '.' ? 1.5 : 1)
  return Number(bpm) >= 20 && Number(bpm) <= 300 ? { beat, bpm: Number(bpm) } : null
}

const scale: Record<Degree, number> = { 1: 0, 2: 2, 3: 4, 4: 5, 5: 7, 6: 9, 7: 11 }

/** A pitch as written: `5`, `#4`, `1'`, `6,,` */
export const parsePitch = (text: string): Pitch | null => {
  const match = /^([#b]?)([1-7])('+|,+)?$/.exec(text)
  if (match === null) return null
  const [, accidental = '', digit = '1', dots = ''] = match
  return pitch(
    Number(digit) as Degree,
    accidentals[accidental],
    dots.startsWith("'") ? dots.length : dots === '' ? 0 : -dots.length,
  )
}

export const pitch = (degree: Degree, accidental: Accidental | undefined, octave: number): Pitch => ({
  degree,
  ...(accidental === undefined ? {} : { accidental }),
  octave,
  semitones: scale[degree] + (accidental === 'sharp' ? 1 : accidental === 'flat' ? -1 : 0) + 12 * octave,
})
