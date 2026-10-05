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

## Version 1

| Part | Scope |
| --- | --- |
| **Library** | Built-in long tones, scales, and études; your own scores |
| **Score** | Jianpu (numbered notation): notes, octave dots, durations, dots, rests, bar lines |
| **Tempo** | Set per score and remembered |
| **Play along** | Count-in; metronome-driven cursor; live comparison of the played pitch with the score's note (high or low, cents) |
| **Settings** | Dizi key (D, C, G, …), fingering system (筒音作 5, 作 2, …), reference pitch (A4 = 440/442 Hz) |

Interface language: Chinese first; strings kept in a String Catalog for later languages.

## Later, in order

1. **Review** after a run: each note's accuracy and stability; pitch curves for long notes.
2. **Fuller notation**: ornaments (颤音, 叠音, 打音, 滑音, 吐音), slurs and ties, repeats.
3. **Accompaniment**: import audio; tempo change without pitch change; transposition; sync with the score.
4. **Score recognition**: photograph a score; a server asks a vision model for the score text; a review screen to correct it.
5. **AI review**: a teacher's comments from a run's data.
6. **Practice records** and **AI-planned practice**, including generated études.

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
