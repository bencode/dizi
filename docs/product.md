# Dizi: product

An iPhone app for practicing the dizi (Chinese bamboo flute) **along a score**.

## The idea

- **Practice is playing a score.** Long tones, scales, études, and pieces are all scores. One practice flow serves them all.
- **Not an open-ended tool.** A tuner or metronome that runs forever has no content and no end, and people drop it. Here every practice has a score, a tempo, and an end.
- **The score knows the target.** Since the score says which note is due, the app can tell how far the note you play is from it, not merely what you play.
- **The product is a practice engine plus a library.** Collect études and songs, organize them, and practice whichever you like.

## Who

Players past the beginner stage, practicing on an iPhone. First user: the author, an advanced amateur.

## Core flow

```text
Library ─▶ open a score ─▶ the score shows ─▶ set the tempo on it ─▶ Start
   ─▶ count-in ─▶ the metronome moves a cursor along the score
   ─▶ you play; the screen shows, live, whether the current note is high or low, in cents
   ─▶ the score ends, practice stops
```

## Phase 1

**Goal**: open a piece, read the jianpu, and play it through with the app's beat and cursor.

**Done when** the author, on their own iPhone, picks a piece from the list, sets the tempo, plays it through with the cursor, and wants to practice again.

```text
Piece list ─tap─▶ score page (jianpu) ─▶ set the tempo / (optional) tap a bar to start there
   ─▶ Start ─▶ count-in ─▶ click + (optional) demo melody + the current note lit, page turning by itself
   ─▶ pause / stop / the end
```

| Part | In phase 1 | Not in phase 1 |
| --- | --- | --- |
| **Piece list** | Grouped by category (long tones, scales, études, pieces); title, key, time signature | Search, filters, favorites, download from a server |
| **Score** | Jianpu: notes, octave dots, 减时线, 增时线, dots, rests, bar lines, accidentals, key, time signature, tempo; lines broken as in the score text; techniques shown as text above the note | Drawn technique symbols, landscape, zoom |
| **Play along** | Count-in; click (on/off); demo melody (on/off); the current note lit; page turning; pause, resume, stop | Looping a passage; a "wait for me" mode |
| **Tempo** | The score's tempo by default; adjustable and remembered per piece | Accelerando, ritardando |
| **Start point** | Tap a bar to start from it | — |
| **Settings** | None; the click and demo sound in the score's key | Dizi key, 筒音作几, A4 (with live pitch, phase 2) |

**Content**: about 10 bundled pieces, public domain only: long tones and scales written for the app, and traditional songs such as 茉莉花. All in our jianpu text format (its spec is drafted and will be published in `docs/`).

**Foundations** laid in phase 1:

- **Score parser**: everything else depends on it.
- **Timeline**: each note's start time and length, computed from the score. The cursor, click, and demo melody follow it; phase 2 aligns pitch with it.
- **Audio out**: click and demo melody through AVAudioEngine.

Interface language: Chinese first; strings kept in a String Catalog for later languages.

## Later, in order

1. **Live pitch** (phase 2): while you play, whether the current note is high or low against the score, in cents. Settings arrive with it: dizi key, 筒音作几, reference pitch (A4 = 440/442 Hz).
2. **Review** after a run: each note's accuracy and stability; pitch curves for long notes.
3. **Fuller notation**: drawn technique symbols (颤音, 叠音, 打音, 滑音, 吐音, …), slurs and ties, repeats.
4. **Practice tools**: looping a passage; a "wait for me" mode that moves on when you play the right note.
5. **Library from a server**, so content updates without a release; your own typed scores.
6. **Accompaniment**: import audio; tempo change without pitch change; transposition; sync with the score.
7. **Score recognition**: photograph a score; a server asks a vision model for the score text; a review screen to correct it.
8. **AI review**: a teacher's comments from a run's data.
9. **Practice records** and **AI-planned practice**, including generated études.

## Design rules

- **Measure on the phone, interpret with AI.** Pitch detection, timing, and audio stay on the device with classic signal processing: exact, real-time, offline. A model turns measurements into comments, plans, and new scores.
- **One score format** for everything: built-in content, typed scores, and recognized scores. The app's parser checks all of it.
- **Offline first.** Everything but the AI features works without a network.

## The library

- **Organized by** category (long tones, scales, technique, études, pieces), difficulty, dizi key and fingering system, and style.
- **Built during development** with a model's help: photographs of the author's scores become score text, which the author checks.
- **Bundled** in version 1; served later, so content updates without a release.
- **Copyright**: record each score's source and status. Traditional and folk pieces are mostly free to use; many études and arrangements are not, and need permission before public distribution.

## Platform

- iPhone only, Swift and SwiftUI; audio with AVAudioEngine (measurement mode, so the system's automatic gain and noise suppression stay out of the pitch detection); signal processing with Accelerate.
- A thin server later, only for AI features (it holds the model key).
- App Store name to decide; candidates include 笛伴 (DiziPal).
