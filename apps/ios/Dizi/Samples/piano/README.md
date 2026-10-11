# Piano voice

The demo melody's sound: a grand piano, one sample every minor third from C4 to C8 (MIDI 60, 63, … 108).

- **Source**: [Salamander Grand Piano V3](https://github.com/sfzinstruments/SalamanderGrandPiano) by Alexander Holm, a Yamaha C5.
- **License**: [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/). The app credits it in 设置, and the repository README credits it too.
- **Changes** (`tools/prepare-samples.py`): velocity layer 10 of 16 only; mixed to mono; cut at the onset and kept for 4 s with a 0.5 s fade-out; every note brought to one loudness over its strike, with the brightest high notes turned down to stay below clipping.

To regenerate, download the 17 source files (`C4v10.flac`, `D#4v10.flac`, … `C8v10.flac`) from the repository's `Samples/` folder into one directory, then run:

```sh
tools/prepare-samples.py <that-directory> apps/ios/Dizi/Samples/piano
```
