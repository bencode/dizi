# Score page

The most important screen: the score, and playing along with it.

## What it does

| # | Job | |
| --- | --- | --- |
| 1 | **Show the whole score** | scrolls; follows the playhead while playing |
| 2 | **Transport** | start, pause, stop; start from any note |
| 3 | **Beat and tempo** | which beat of the bar is sounding; change the tempo |

## 走谱

Pressing 开始 counts in one bar, clicks every beat (accent on each bar's downbeat), and moves the playhead along the score while the player plays. With **示范** on, the app plays the melody too, with real dizi samples (`apps/ios/Dizi/Samples/dizi-c`, CC0), retuned to A4 = 440.

- **Octave**: an undotted `1` is the tonic in A4…G♯5, where 筒音作5 puts it on the flute in that key (1=D → D5, 1=F → F5). Settings for the flute and 筒音作几 will override this later.
- **Sync**: the whole melody of a run is rendered into one buffer and starts on the same sample as the clicks.

**Audio is the clock.** Clicks are scheduled sample-accurately in the audio engine; every frame the page reads the engine's time and a pure function (`Run.position`) says which note is sounding. Timers would drift.

## One playhead

The start point and the playing position are one thing: the **playhead**, like the dot on a video's progress bar, but on the score.

```text
stopped --tap a note--------------▶ stopped, playhead on that note
stopped --Start-------------------▶ count-in ─▶ playing from the playhead
playing --as time passes----------▶ the line fills up to the playhead, continuously; current note lit
playing --Pause-------------------▶ paused, playhead stays
paused  --Start-------------------▶ count-in ─▶ playing from the playhead
playing --Stop / end of score-----▶ stopped, playhead back at the chosen start
```

- The playhead **snaps to a note**: starting in the middle of a note makes no sense.
- While playing it **reaches each note's digit exactly when the note should start**, and moves smoothly in between (a monotone cubic through those points), so bar lines and uneven spacing cause no lurch.
- While playing, tempo and switches are locked; pause or stop to change them.

## Layers

The page is drawn in layers over one shared layout, so later features add a layer without touching the ones below.

| Layer | Draws | How |
| --- | --- | --- |
| 0 **Layout** | where every note, line, and bar goes, from the [IR](score-ir.md) and the screen width | pure computation, no drawing; unit tested ("this note is on line 2", "this 减时线 joins these two notes") |
| 1 **Notation** | digits, octave dots, 减时线, 增时线, dots, bar lines | SwiftUI `Canvas` |
| 2 **Symbols** | techniques, slurs, graces, marks | `Canvas` |
| 3 **Playhead** | current note lit, start marker | SwiftUI views over the canvas, animated |
| 4 **Feedback** (phase 2) | high or low, in cents | views |
| later | fingering hints, pitch curves in review | |

Every element the layout places carries its note id and start tick, so each layer finds its position by id or by time.

## Static notation, in steps

| Step | Adds |
| --- | --- |
| 1 | digits, octave dots, bar lines, line breaks, the header (`1=F 2/4`) |
| 2 | 减时线 joined per beat, 增时线, dots, rests |
| 3 | accidentals, slurs and ties, graces |
| 4 | dizi technique symbols |

Then interaction: playhead, playback, beat.

## Slurs, ties, breath

- A slur or tie is an arc above its notes, from the first digit to the last, lifted clear of the digits and high-octave dots under it. Across a line break it is split: to the right edge on the first line, edge to edge on lines it spans, from the left edge on the last.
- A breath mark `V` sits above the line, halfway between the note it follows and the next note (or at the line's end).
- The demo plays a tie as one note, and the notes of a slur after its first without a new attack (they crossfade from the note before), the way a slur is played on the dizi: only its first note is tongued.

## Layout

```text
┌─────────────────────────────┐
│ ‹ 曲目        茉莉花          │
│ 1=F  2/4  ♩=72               │  header
├─────────────────────────────┤
│                             │
│   score (layers, scrolls)   │
│                             │
├─────────────────────────────┤
│ ● ○        ♩=72   −  +       │  beat · tempo
│ [▶]        节拍 ●  示范 ○     │  transport · click and demo switches
└─────────────────────────────┘
```

- The transport bar sits at the bottom, where the thumb reaches.
- **Lines fill the width**: each line takes as many measures as fit, so lines hold different numbers of measures. Every line but the last is stretched to both edges.
- **A section starts a new line**: 【一】, 引子, 散板 … always begin at the left edge.
- **Printed line breaks are not followed**: they are only the engraver's choice for paper width. The IR keeps them (`layoutHints`) for a later "match the printed page" mode.
- **Spacing follows length**: shorter notes sit closer; each 增时线 takes a quarter's width.
- **Everything scales from one font size**: landscape is a wider width, larger or smaller text is a different font size; both are just a relayout. One fixed size in phase 1; the size control and landscape come later.
- Light and dark follow the system.
