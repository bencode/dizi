import Foundation

/// A recorded note to build the melody from: samples, the note it is, how far off tune it was recorded,
/// and the stretch that repeats to sustain it.
public struct Voice: Sendable {
    public let samples: [Float]
    public let sampleRate: Double
    public let midi: Int
    public let tuneCents: Double
    public let loop: Range<Int>

    public init(samples: [Float], sampleRate: Double, midi: Int, tuneCents: Double, loop: Range<Int>) {
        self.samples = samples
        self.sampleRate = sampleRate
        self.midi = midi
        self.tuneCents = tuneCents
        self.loop = loop
    }
}

/// How long a note fades after its written end.
let releaseSeconds = 0.04

/// The melody as one mono signal at `sampleRate`: each note from the nearest voice, retuned to pitch,
/// sustained by looping, faded out at its end; overlapping tails mix.
public func melodySamples(_ notes: [MelodyNote], voices: [Voice], sampleRate: Double) -> [Float] {
    let length = notes.map { Int(((($0.time + $0.duration + releaseSeconds) * sampleRate)).rounded(.up)) }.max() ?? 0
    var mix = [Float](repeating: 0, count: length)
    for note in notes {
        guard let voice = voices.min(by: { abs($0.midi - note.midi) < abs($1.midi - note.midi) }) else { continue }
        let start = Int((note.time * sampleRate).rounded())
        let sound = sustained(
            voice, step: playbackStep(voice, midi: note.midi, sampleRate: sampleRate),
            count: Int((note.duration + releaseSeconds) * sampleRate),
            fadeFrom: Int(note.duration * sampleRate))
        for (offset, value) in sound.enumerated() where start + offset < length {
            mix[start + offset] += value * 0.8
        }
    }
    return mix
}

/// How many voice samples to advance per output sample to sound `midi` in tune.
func playbackStep(_ voice: Voice, midi: Int, sampleRate: Double) -> Double {
    let semitones = Double(midi - voice.midi) - voice.tuneCents / 100
    return pow(2, semitones / 12) * voice.sampleRate / sampleRate
}

/// `count` samples of a voice read at `step`, looping its sustain, fading linearly to silence from `fadeFrom`.
private func sustained(_ voice: Voice, step: Double, count: Int, fadeFrom: Int) -> [Float] {
    let fadeLength = Double(max(count - fadeFrom, 1))
    return (0..<count).map { index in
        let gain = index < fadeFrom ? 1 : Float(1 - Double(index - fadeFrom) / fadeLength)
        return gain * interpolated(voice, at: looped(Double(index) * step, voice.loop))
    }
}

/// A read position folded back into the loop once it passes the loop's end.
private func looped(_ position: Double, _ loop: Range<Int>) -> Double {
    let (start, end) = (Double(loop.lowerBound), Double(loop.upperBound))
    guard position >= end, end > start else { return position }
    return start + (position - start).truncatingRemainder(dividingBy: end - start)
}

private func interpolated(_ voice: Voice, at position: Double) -> Float {
    let index = Int(position)
    guard index + 1 < voice.samples.count else { return voice.samples.last ?? 0 }
    let fraction = Float(position - Double(index))
    return voice.samples[index] * (1 - fraction) + voice.samples[index + 1] * fraction
}
