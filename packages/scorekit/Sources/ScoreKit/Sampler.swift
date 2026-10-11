import Foundation

/// A recorded note to build the melody from: its samples and the note it is.
public struct Voice: Sendable {
    public let samples: [Float]
    public let sampleRate: Double
    public let midi: Int

    public init(samples: [Float], sampleRate: Double, midi: Int) {
        self.samples = samples
        self.sampleRate = sampleRate
        self.midi = midi
    }
}

/// How long a note fades after its written end, as a piano's damper.
let releaseSeconds = 0.15

/// The melody as one mono signal at `sampleRate`: each note struck from the nearest voice, retuned to pitch,
/// sounding while its recording lasts and faded out at its end; overlapping tails mix.
public func melodySamples(_ notes: [MelodyNote], voices: [Voice], sampleRate: Double) -> [Float] {
    let length = notes.map { Int(((($0.time + $0.duration + releaseSeconds) * sampleRate)).rounded(.up)) }.max() ?? 0
    var mix = [Float](repeating: 0, count: length)
    for note in notes {
        guard let voice = voices.min(by: { abs($0.midi - note.midi) < abs($1.midi - note.midi) }) else { continue }
        let start = Int((note.time * sampleRate).rounded())
        for (offset, value) in sounded(note, voice: voice, sampleRate: sampleRate).enumerated()
        where start + offset < length {
            mix[start + offset] += value * 0.8
        }
    }
    return mix
}

/// How many voice samples to advance per output sample to sound `midi`.
func playbackStep(_ voice: Voice, midi: Int, sampleRate: Double) -> Double {
    pow(2, Double(midi - voice.midi) / 12) * voice.sampleRate / sampleRate
}

/// One note read from its voice and retuned, fading linearly to silence after its written end.
private func sounded(_ note: MelodyNote, voice: Voice, sampleRate: Double) -> [Float] {
    let step = playbackStep(voice, midi: note.midi, sampleRate: sampleRate)
    let (count, fadeFrom) = (Int((note.duration + releaseSeconds) * sampleRate), Int(note.duration * sampleRate))
    let fadeLength = Double(max(count - fadeFrom, 1))
    return (0..<count).map { index in
        let fadeOut = index < fadeFrom ? 1 : Float(1 - Double(index - fadeFrom) / fadeLength)
        return fadeOut * interpolated(voice, at: Double(index) * step)
    }
}

/// The voice between two samples; silent once its recording has ended.
private func interpolated(_ voice: Voice, at position: Double) -> Float {
    let index = Int(position)
    guard index + 1 < voice.samples.count else { return 0 }
    let fraction = Float(position - Double(index))
    return voice.samples[index] * (1 - fraction) + voice.samples[index + 1] * fraction
}
