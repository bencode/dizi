# Dizi voice (C调笛)

The demo melody's sound: one sample per naturally fingered note of a C dizi, G4 to G6 (MIDI 67–91).

- **Source**: "Flute Dizi C all notes + pitched semitones" by Hypnotriod, https://freesound.org/people/Hypnotriod/packs/21613/
- **License**: CC0 1.0 (public domain). No attribution is required; we credit the recording anyway, with thanks.
- **Processing** (`tools/prepare-samples.py`): only the 15 recorded notes are kept (the pack's semitones are pitch-shifted copies); each is cut at its onset to 3 s, with a loop taken from its straight part (before the vibrato starts) and crossfaded at the seam. `manifest.json` stores each note's measured tuning (`tuneCents`), corrected when the app plays it, and its loop points in samples.
