#!/usr/bin/env python3
"""Prepares the demo-melody voice from the CC0 dizi pack (freesound.org/people/Hypnotriod/packs/21613).

For each recorded note (the pack's other files are pitch-shifted copies): measure its tuning on the straight
part, cut attack + a loop taken from the straight part (before the player adds 气震音), crossfade the loop's
end into its start so the seam is continuous, and write a CAF plus a manifest entry.

Usage: tools/prepare-samples.py <pack-directory> <output-directory>
"""
import glob
import json
import os
import re
import subprocess
import sys
import tempfile
import wave

import numpy as np

RECORDED = [67, 69, 71, 72, 74, 76, 78, 79, 81, 83, 84, 86, 88, 90, 91]
LOOP_START, LOOP_END, CROSSFADE = 1.2, 3.0, 0.1  # seconds from the note's onset


def read(path):
    with wave.open(path) as w:
        data = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float64) / 32768
        return data, w.getframerate()


def fundamental(frame, rate, low=300, high=2200):
    """YIN: the lag where the signal best repeats, refined between samples."""
    taus = np.arange(int(rate / high), int(rate / low))
    half = len(frame) // 2
    diff = np.array([np.sum((frame[:half] - frame[t:t + half]) ** 2) for t in taus])
    normalized = diff * taus / np.cumsum(diff)
    candidates = np.where(normalized < 0.15)[0]
    i = candidates[0] if len(candidates) else int(np.argmin(normalized))
    while i + 1 < len(normalized) and normalized[i + 1] < normalized[i]:
        i += 1
    if 0 < i < len(normalized) - 1:
        a, b, c = normalized[i - 1], normalized[i], normalized[i + 1]
        i = i + 0.5 * (a - c) / (a - 2 * b + c)
    return rate / (taus[0] + i)


def onset(x, rate):
    hop = int(rate * 0.01)
    rms = np.array([np.sqrt(np.mean(x[i:i + hop] ** 2)) for i in range(0, len(x) - hop, hop)])
    return max(0, int(np.argmax(rms > rms.max() * 0.1)) * hop - int(rate * 0.005))


def cents_off(x, rate, midi):
    target = 440 * 2 ** ((midi - 69) / 12)
    frames = range(int(0.5 * rate), int(LOOP_END * rate), 2048)
    return float(np.median([1200 * np.log2(fundamental(x[i:i + 2048], rate) / target) for i in frames]))


def aligned_end(x, loop_start, target, rate):
    """The loop end near `target` whose preceding waveform best matches the one before the loop start,
    so the crossfade joins two signals in phase instead of partly cancelling them."""
    window, reach = 256, int(rate * 0.01)
    before_start = x[loop_start - window:loop_start]
    return min(range(target - reach, target + reach),
               key=lambda end: float(np.sum((x[end - window:end] - before_start) ** 2)))


def prepared(path, midi):
    raw, rate = read(path)
    x = raw[onset(raw, rate):]
    loop_start, fade = int(LOOP_START * rate), int(CROSSFADE * rate)
    loop_end = aligned_end(x, loop_start, int(LOOP_END * rate), rate)
    out = x[:loop_end].copy()
    ramp = np.linspace(0, 1, fade)
    out[loop_end - fade:loop_end] = x[loop_end - fade:loop_end] * (1 - ramp) + x[loop_start - fade:loop_start] * ramp
    return out, rate, {"midi": midi, "tuneCents": round(cents_off(x, rate, midi), 1),
                       "loopStart": loop_start, "loopEnd": loop_end}


def write_caf(samples, rate, path):
    with tempfile.NamedTemporaryFile(suffix=".wav") as tmp:
        with wave.open(tmp.name, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(rate)
            w.writeframes((np.clip(samples, -1, 1) * 32767).astype(np.int16).tobytes())
        subprocess.run(["afconvert", "-f", "caff", "-d", "LEI16", tmp.name, path], check=True)


def main(pack, output):
    entries = []
    for midi in RECORDED:
        path = glob.glob(os.path.join(pack, f"*_{midi:03d}_*.wav"))[0]
        samples, rate, entry = prepared(path, midi)
        write_caf(samples, rate, os.path.join(output, f"{midi}.caf"))
        entries.append({**entry, "sampleRate": rate})
        print(f"{midi}: tune {entry['tuneCents']:+.1f} cents, {len(samples) / rate:.2f} s")
    with open(os.path.join(output, "manifest.json"), "w") as f:
        json.dump({"source": "https://freesound.org/people/Hypnotriod/packs/21613/", "license": "CC0-1.0",
                   "voices": entries}, f, indent=2)
        f.write("\n")


if __name__ == "__main__":
    main(*sys.argv[1:3])
