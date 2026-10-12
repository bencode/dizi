# Tuner (调音器)

A page for tuning the flute before practice and for checking single notes. It opens from the tuning fork next to the gear on the 练习 tab.

## What it shows

| Element | What it is |
| --- | --- |
| Note | The note being blown, as a jianpu digit with its octave dots and ♯/♭. It is read on the flute and fingering chosen at the top, and both are remembered. |
| Concert name and frequency | For example `A4 · 441.6 Hz`. The reference is A4 = 440 Hz. |
| Needle and cents | The distance to the nearest equal-tempered note, from −50 to +50 cents. Within ±5 cents it reads 准; otherwise 偏高 or 偏低, in accent. |
| Breath time | 这口气 is how long the current sound has lasted. A gap over 0.3 s ends it. 最长 is the longest breath on this visit. |

To tune the flute, blow the 筒音 and pull or push the joint until it reads 准.

## Flutes

The jianpu is read from the flute's 筒音 (all holes closed), in concert pitch:

| Flute | 大G | 大A | 大♭B | C | D | E | F | G |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 筒音 | D4 | E4 | F4 | G4 | A4 | B4 | C5 | D5 |

Middle 1 sits an octave above the 筒音's degree:
- D flute, 筒音作5: 1 = D5 and the 筒音 reads 5̣.
- D flute, 筒音作2: 1 = G5 and the 筒音 reads 2̣.

Chromatic notes read ♯1 ♯2 ♯4 ♯5 ♭7.

## How it listens

- The microphone runs in measurement mode, with no voice processing.
- Every new block of sound gives a window of 4096 samples, about 90 ms.
- ScoreKit's `detectedFrequency` finds the pitch with YIN, between 250 and 2500 Hz. The page shows the median of the last three readings.
- Nothing is recorded or stored. Each window is analysed in memory and dropped.
- The microphone is released when the page closes, so music it interrupted can resume.
