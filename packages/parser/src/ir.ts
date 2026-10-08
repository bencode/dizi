// The score IR, as specified in docs/score-ir.md. Field order matches the spec so the JSON reads the same.

export type Degree = 1 | 2 | 3 | 4 | 5 | 6 | 7
export type Accidental = 'sharp' | 'flat'
export type Letter = 'C' | 'D' | 'E' | 'F' | 'G' | 'A' | 'B'

export type Key = { tonic: Letter; accidental?: Accidental }

export type Pitch = {
  degree: Degree
  accidental?: Accidental
  octave: number
  semitones: number
}

export type Meter = { beats: number; unit: 2 | 4 | 8 | 16 }
export type Time = Meter | 'free'

export type NoteValue = 1 | 2 | 4 | 8 | 16 | 32 | 64
export type Dots = 0 | 1 | 2

export type Technique =
  | { type: 't' }
  | { type: 'k' }
  | { type: 'qingtu' }
  | { type: 'baochi' }
  | { type: 'qiang' }
  | { type: 'tr'; to?: Pitch }
  | { type: 'feizhi' }
  | { type: 'slide'; direction: 'up' | 'down'; from?: Pitch }
  | { type: 'yuanhua'; via: Pitch }
  | { type: 'huashe' }
  | { type: 'duo'; from: Pitch }
  | { type: 'zhizhen' }
  | { type: 'die' }
  | { type: 'da' }
  | { type: 'fan' }
  | { type: 'bo'; direction: 'up' | 'down' }
  | { type: 'rou' }
  | { type: 'hou' }
  | { type: 'fuzhen' }
  | { type: 'qizhen' }
  | { type: 'yanchang' }

export type Grace = { position: 'before' | 'after'; pitches: Pitch[] }

export type Note = {
  kind: 'note'
  id: string
  start: number
  duration: number
  value: NoteValue
  dots: Dots
  pitch: Pitch
  techniques?: Technique[]
  graces?: Grace[]
}

export type Rest = {
  kind: 'rest'
  id: string
  start: number
  duration: number
  value: NoteValue
  dots: Dots
  techniques?: Technique[]
}

export type Event = Note | Rest

export type Beam = { level: number; from: string; to: string }

export type Barline = 'single' | 'double' | 'final'

export type Measure = {
  index: number
  start: number
  duration: number
  time: Time
  barline: Barline
  repeatStart?: true
  repeatEnd?: true
  /** The passes through a repeat this measure is played on: an ending (1., 2.). */
  volta?: number[]
}

export type PartMeasure = { events: Event[]; beams: Beam[] }

export type Part = { id: string; role: 'solo' | 'accompaniment'; measures: PartMeasure[] }

export type Span =
  | { type: 'slur'; from: string; to: string }
  | { type: 'tie'; from: string; to: string }
  | { type: 'tuplet'; actual: 3; normal: 2; from: string; to: string }

export type Mark =
  | { kind: 'section'; at: number; label: string }
  | { kind: 'tempo'; at: number; beat: number; bpm: number }
  | { kind: 'breath'; at: number; style: 'normal' | 'circular' }
  | { kind: 'keyChange'; at: number; key: Key }

export type Score = {
  irVersion: 1
  meta: { title?: string; composer?: string }
  header: { key: Key; fingering?: { degree: Degree; octave: number } }
  ticksPerQuarter: 480
  measures: Measure[]
  playOrder: number[]
  parts: Part[]
  spans: Span[]
  marks: Mark[]
  layoutHints?: { lineBreaksAfter: number[] }
}
