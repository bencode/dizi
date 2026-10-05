# Score page

The most important screen: the score, and playing along with it.

## What it does

| # | Job | |
| --- | --- | --- |
| 1 | **Show the whole score** | scrolls; follows the playhead while playing |
| 2 | **Transport** | start, pause, stop; start from any note |
| 3 | **Beat and tempo** | which beat of the bar is sounding; change the tempo |

## One playhead

The start point and the playing position are one thing: the **playhead**, like the dot on a video's progress bar, but on the score.

```text
stopped --tap a note--------------▶ stopped, playhead on that note
stopped --Start-------------------▶ count-in ─▶ playing from the playhead
playing --each note---------------▶ playhead moves, current note lit
playing --Pause-------------------▶ paused, playhead stays
paused  --Start-------------------▶ count-in ─▶ playing from the playhead
playing --Stop / end of score-----▶ stopped, playhead back at the chosen start
```

- The playhead **snaps to a note**: starting in the middle of a note makes no sense.
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
