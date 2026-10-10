# Score IR

The score IR is what every app reads: a JSON description of the **music** in a score. The parser (TypeScript, later) compiles score text into it once; iOS, Android, and Web each lay it out and draw it.

```text
score text ──parser──▶ IR (JSON) ──app──▶ layout (needs screen width) ──▶ drawing
             server / scripts      platform-independent      on the device only
```

## Principles

- **Music, not notation.** The IR says what is played: which note, when, how long, with which technique. How it looks (jianpu, staff, which glyph) is the renderer's decision.
- **Compute once.** Anything every platform would otherwise recompute, and could get wrong, is in the IR: start times, durations, ids, beam groups, the repeat play order.
- **Layout stays on the device.** Positions, line wrapping, sizes, and colors depend on the screen.
- **Unknown is ignored.** A renderer skips a `kind` or `type` it does not know; the score still shows and plays. New techniques and marks are added this way without breaking older apps.
- **`irVersion`** changes only for a breaking change.

## Time

| | Unit | Where |
| --- | --- | --- |
| **Musical time** | ticks; a quarter note is 480 | in the IR (`start`, `duration`) |
| **Real time** | seconds | computed at playback from the tempo, which the player can change |

480 divides by 2, 3, 4, 5, 6, 8, 10, 12, 16; tuplets keep exact integer durations. `start` counts from the beginning of the score; repeats do not shift it (see `playOrder`).

## Pitch

A pitch is a **scale degree in the key**, as the score writes it: jianpu shows the degree; a staff renderer turns degree + key into a letter.

```ts
type Degree = 1 | 2 | 3 | 4 | 5 | 6 | 7
type Accidental = 'sharp' | 'flat'
type Key = { tonic: 'C' | 'D' | 'E' | 'F' | 'G' | 'A' | 'B'; accidental?: Accidental }   // 1=bB → { tonic: 'B', accidental: 'flat' }

type Pitch = {
  degree: Degree
  accidental?: Accidental      // this note only; never carried through the bar
  octave: number               // dots: +1 per dot above, -1 per dot below
  semitones: number            // from the undotted 1, e.g. 5̣ → -5, 1̇ → 12, #4 → 6
}
```

`semitones` is relative. The absolute octave of an undotted `1` depends on the flute and 筒音作几, which are the player's settings; playback and pitch checking resolve it on the device.

## Score

```ts
type Score = {
  irVersion: 1
  meta: { title?: string; composer?: string; arranger?: string }
  header: {
    key: Key
    keyAlternatives?: Key[]                      // 1=G或F → key G, alternatives [F]
    flute?: Key                                  // G调笛
    fingering?: { degree: Degree; octave: number }   // 筒音作2̣ → { degree: 2, octave: -1 }
  }
  ticksPerQuarter: 480
  measures: Measure[]          // the shared bar grid
  playOrder: number[]          // measure indices in playing order, repeats unrolled
  parts: Part[]                // solo first
  spans: Span[]                // form C
  marks: Mark[]                // form D
  layoutHints?: { lineBreaksAfter: number[] }   // where the source breaks lines; renderers may ignore it
}

type Measure = {
  index: number
  start: number
  duration: number
  time: { beats: number; unit: 2 | 4 | 8 | 16 } | 'free'   // 'free' = 散板: no beat, bars not checked
  barline: 'single' | 'double' | 'final'
  repeatStart?: true
  repeatEnd?: true
  volta?: number[]             // the ending this bar belongs to: [1], [2], [1, 2]
}

type Part = {
  id: string
  role: 'solo' | 'accompaniment'   // phase 1 draws and plays only the solo
  measures: PartMeasure[]          // same length and order as Score.measures
}

type PartMeasure = {
  events: Event[]
  beams: Beam[]
}

/** Short notes joined per beat: one line in jianpu (减时线), a beam in staff. */
type Beam = { level: number; from: string; to: string }   // level 1 = eighths, 2 = sixteenths …
```

## Notes and rests

```ts
type Event = Note | Rest

type Note = {
  kind: 'note'
  id: string                   // unique in the score; spans refer to it
  start: number
  duration: number             // actual length, tuplets applied
  value: 1 | 2 | 4 | 8 | 16 | 32 | 64   // written value: 4 = quarter, 8 = eighth
  dots: 0 | 1 | 2
  pitch: Pitch
  techniques?: Technique[]     // form A
  graces?: Grace[]             // form B
}

type Rest = {
  kind: 'rest'
  id: string
  start: number
  duration: number
  value: 1 | 2 | 4 | 8 | 16 | 32 | 64
  dots: 0 | 1 | 2
  techniques?: Technique[]     // only 'yanchang' (延长记号)
}
```

`value` and `dots` are the written length, which both notations derive their symbols from: jianpu draws an eighth as one 减时线 and a half note as `5 -`; staff draws the matching note heads.

## The four forms

Everything written on a dizi score besides notes and rests takes one of four forms.

| Form | Where it hangs | Examples |
| --- | --- | --- |
| **A** | on one note: `Note.techniques` | 颤音, 叠音, 打音, 吐音, 花舌, 波音 |
| **B** | small notes with their own pitch: `Note.graces` | 倚音, 赠音 |
| **C** | from one note to another: `Score.spans` | 连线, 延音线, 历音, 连音, tr~~ held over a passage |
| **D** | at a moment, not on a note: `Score.marks` | 段落, 速度, 力度, 表情文字, 换气, 循环换气 |

### A — techniques on a note

Names are the pinyin of the Chinese term, as in the score text.

```ts
type Technique =
  | { type: 't' }                                   // 吐: 单吐; with 'k' forms 双吐 (TK) and 三吐 (TTK, TKT)
  | { type: 'k' }                                   // 苦
  | { type: 'qingtu' }                              // 轻吐 ⊙
  | { type: 'baochi' }                              // 保持音 −
  | { type: 'qiang' }                               // 强音 >
  | { type: 'tr'; to?: Pitch }                      // 颤音; with `to`: 多度颤音 (trill to the marked note)
  | { type: 'feizhi' }                              // 飞指
  | { type: 'slide'; direction: 'up' | 'down'; from?: Pitch }   // 上滑音, 下滑音 (/ or a small start note)
  | { type: 'yuanhua'; via: Pitch }                 // 圆滑音: up to `via`, back down
  | { type: 'huashe' }                              // 花舌 ☆
  | { type: 'duo'; from: Pitch }                    // 剁音: struck hard from `from`
  | { type: 'zhizhen' }                             // 指震音
  | { type: 'die'; pitches?: Pitch[] }              // 叠音 又, optionally with its written upper notes
  | { type: 'da' }                                  // 打音 丅
  | { type: 'fan' }                                 // 泛音 ○
  | { type: 'bo'; direction: 'up' | 'down' }        // 上波音 (121), 下波音 (171)
  | { type: 'rou' }                                 // 揉音 ∪
  | { type: 'hou' }                                 // 喉音 ⊗
  | { type: 'fuzhen' }                              // 大腹震音
  | { type: 'qizhen' }                              // 气震音
  | { type: 'yanchang' }                            // 延长记号 𝄐
```

### B — graces

```ts
type Grace = {
  position: 'before' | 'after'   // 倚音 before the note, 赠音 after it
  pitches: Pitch[]               // one or many, in playing order
}
```

Graces take no written time; playback borrows a short moment from the main note (before) or the end of it (after).

### C — spans

```ts
type Span =
  | { type: 'slur'; from: string; to: string }                          // 连线: no tonguing, no breath inside
  | { type: 'tie'; from: string; to: string }                           // 延音线: same pitch, one long note
  | { type: 'slide'; from: string; to: string }                         // 连线滑音: glide from one note to the next
  | { type: 'li'; direction: 'up' | 'down'; from: string; to: string }  // 历音: a fast scale run between two notes
  | { type: 'tuplet'; actual: number; normal: number; from: string; to: string }   // 3 in the time of 2 … (the parser writes triplets only: actual 3, normal 2)
  | { type: 'technique'; technique: Technique; from: string; to: string }          // tr~~, 花舌---, TK---, 喉音---
  | { type: 'hairpin'; direction: 'cresc' | 'dim'; from: string; to: string }
  | { type: 'tempoChange'; direction: 'accel' | 'rit'; text?: string; from: string; to: string }   // 渐快, 渐慢
  | { type: 'bracket'; text: string; from: string; to: string }         // e.g. 吐滑结合
```

`from` and `to` are note or rest ids, in any part; a span may cross measures.

### D — marks

```ts
type Mark =
  | { kind: 'section'; at: number; label: string }                      // 【一】, 引子, 散板, 尾声
  | { kind: 'tempo'; at: number; beat: number; bpm?: number | { min: number; max: number }; text?: string }
                                                                        // ♩=72 → beat 480, bpm 72; 慢板(♩=58~80)
  | { kind: 'dynamic'; at: number; value: 'ppp' | 'pp' | 'p' | 'mp' | 'mf' | 'f' | 'ff' | 'fff' | 'sfp' | 'sf' }
  | { kind: 'text'; at: number; text: string }                          // 清脆地, （百灵鸟）, rit.
  | { kind: 'breath'; at: number; style: 'normal' | 'circular' }        // 换气 V, 循环换气 ⓥ
  | { kind: 'keyChange'; at: number; key: Key; flute?: Key; fingering?: { degree: Degree; octave: number } }
                                                                        // 转 1=C（筒音作5）
```

`at` is a tick. A score's starting tempo is a `tempo` mark at 0.

## Rules

- `Part.measures[i]` covers `Score.measures[i]`: its events start at `measures[i].start` and their durations sum to `measures[i].duration` (except `'free'` measures, which take whatever their events add up to).
- Events in a measure are in time order with no gaps: each `start` is the previous `start + duration`.
- Every id referenced by a span or beam exists.
- `playOrder` lists every measure the player passes, in order. With no repeats it is `[0, 1, 2, …]`. The parser computes it: walk the measures; at a `repeatEnd`, go back to the last `repeatStart` (or measure 0) until the repeat has been played as many times as its highest ending (at least twice); on pass *n*, skip measures whose `volta` does not contain *n*.
- An ending (`volta`) carries over the following measures until another ending starts, or ends after a measure with `repeatEnd` or a double or final bar line.

## Not covered yet

| Written on scores | Plan |
| --- | --- |
| Rhythm-only notes `X` | a future `kind` |
| Alternative melodies above the line ("上方带括号的旋律也可使用") | later |
| "同（…）" abbreviations | the compiler expands them into real notes |
| Footnotes ① | later |
| `2(2)`, `≡` over `tr`, the 气震音 symbol | meaning unknown; decided when found in a reference |

## Example

The opening of 茉莉花 (traditional), `1=F`, `2/4`, `♩=72`:

```text
3 3_ 5_ | 6_ 1'_ 1'_ 6_ |
5 5_ 6_ | 5 - |]
```

The full IR is [examples/molihua.ir.json](examples/molihua.ir.json). Its first measure:

```json
{
  "events": [
    { "kind": "note", "id": "n1", "start": 0,   "duration": 480, "value": 4, "dots": 0,
      "pitch": { "degree": 3, "octave": 0, "semitones": 4 } },
    { "kind": "note", "id": "n2", "start": 480, "duration": 240, "value": 8, "dots": 0,
      "pitch": { "degree": 3, "octave": 0, "semitones": 4 } },
    { "kind": "note", "id": "n3", "start": 720, "duration": 240, "value": 8, "dots": 0,
      "pitch": { "degree": 5, "octave": 0, "semitones": 7 } }
  ],
  "beams": [{ "level": 1, "from": "n2", "to": "n3" }]
}
```
