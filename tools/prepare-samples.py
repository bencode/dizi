#!/usr/bin/env python3
"""Prepares the demo-melody voice from the Salamander Grand Piano V3 (CC BY 3.0, Alexander Holm,
github.com/sfzinstruments/SalamanderGrandPiano).

For each kept note (C4 to C8, a sample every minor third, velocity layer 10 of 16): decode the FLAC, mix to mono,
cut at the onset, keep the first seconds with a fade to silence, even out the loudness across the notes (one RMS
over the strike, as loud as the clicks), and write a CAF plus a manifest entry.

Usage: tools/prepare-samples.py <flac-directory> <output-directory>
"""
import json
import os
import subprocess
import sys
import tempfile
import wave

import numpy as np

NAMES = ["C", "D#", "F#", "A"]
KEPT = range(60, 109, 3)  # MIDI C4 … C8
LAYER = 10
LENGTH, FADE = 4.0, 0.5  # seconds kept from the onset; the last FADE of them fades out
STRIKE, LOUDNESS = 0.3, 0.2  # every note's RMS over its first STRIKE seconds
PEAK = 0.95  # no sample above it: a bright high note is turned down instead


def name(midi):
    return f"{NAMES[(midi % 12) // 3]}{midi // 12 - 1}v{LAYER}.flac"


def read(path):
    """The file as mono samples in -1…1, and its rate."""
    with tempfile.NamedTemporaryFile(suffix=".wav") as tmp:
        subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16", path, tmp.name], check=True)
        with wave.open(tmp.name) as w:
            data = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float64) / 32768
            return data.reshape(-1, w.getnchannels()).mean(axis=1), w.getframerate()


def onset(x, rate):
    hop = int(rate * 0.01)
    rms = np.array([np.sqrt(np.mean(x[i:i + hop] ** 2)) for i in range(0, len(x) - hop, hop)])
    return max(0, int(np.argmax(rms > rms.max() * 0.1)) * hop - int(rate * 0.005))


def prepared(path):
    raw, rate = read(path)
    out = raw[onset(raw, rate):][:int(LENGTH * rate)].copy()
    fade = int(FADE * rate)
    out[-fade:] *= np.linspace(1, 0, fade)
    return out, rate


def write_caf(samples, rate, path):
    with tempfile.NamedTemporaryFile(suffix=".wav") as tmp:
        with wave.open(tmp.name, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(rate)
            w.writeframes((np.clip(samples, -1, 1) * 32767).astype(np.int16).tobytes())
        subprocess.run(["afconvert", "-f", "caff", "-d", "LEI16", tmp.name, path], check=True)


def evened(samples, rate):
    """The note at the set's loudness, or quieter where that would push a sample past PEAK."""
    gain = LOUDNESS / np.sqrt(np.mean(samples[:int(STRIKE * rate)] ** 2))
    return samples * min(gain, PEAK / np.abs(samples).max())


def main(source, output):
    entries = []
    for midi in KEPT:
        raw, rate = prepared(os.path.join(source, name(midi)))
        samples = evened(raw, rate)
        write_caf(samples, rate, os.path.join(output, f"{midi}.caf"))
        entries.append({"midi": midi, "sampleRate": rate})
        print(f"{midi}: {name(midi)}, peak {np.abs(samples).max():.2f}")
    with open(os.path.join(output, "manifest.json"), "w") as f:
        json.dump({"source": "https://github.com/sfzinstruments/SalamanderGrandPiano", "license": "CC-BY-3.0",
                   "voices": entries}, f, indent=2)
        f.write("\n")


if __name__ == "__main__":
    main(*sys.argv[1:3])
