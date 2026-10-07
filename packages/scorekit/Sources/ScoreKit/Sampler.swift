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

/// How long a note fades after its written end; a legato note fades in over the same time, so the two crossfade.
let releaseSeconds = 0.04

/// A tongued note's attack: the recordings jump to full level within milliseconds (a knock) and waver for their
/// first second, so the attack starts a little in, rises softly, and soon hands over to the steady sustain.
let attackSkipSeconds = 0.03
let attackRiseSeconds = 0.01
let attackHoldSeconds = 0.08
let attackHandoverSeconds = 0.02

/// The melody as one mono signal at `sampleRate`: each note from the nearest voice, retuned to pitch,
/// sustained by looping, faded out at its end; overlapping tails mix. A legato note skips the voice's attack.
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

/// How many voice samples to advance per output sample to sound `midi` in tune.
func playbackStep(_ voice: Voice, midi: Int, sampleRate: Double) -> Double {
    let semitones = Double(midi - voice.midi) - voice.tuneCents / 100
    return pow(2, semitones / 12) * voice.sampleRate / sampleRate
}

/// One note read from its voice and retuned, fading linearly to silence after its written end. The sustain reads
/// from the loop's start and loops; a legato note fades straight into it, a tongued note first plays the
/// recording's attack, then crossfades into it.
private func sounded(_ note: MelodyNote, voice: Voice, sampleRate: Double) -> [Float] {
    let samples = { (seconds: Double) in seconds * sampleRate }
    let step = playbackStep(voice, midi: note.midi, sampleRate: sampleRate)
    let (count, fadeFrom) = (Int(samples(note.duration + releaseSeconds)), Int(samples(note.duration)))
    let fadeLength = Double(max(count - fadeFrom, 1))
    let sustainStart = Double(voice.loop.lowerBound)
    let attackStart = attackSkipSeconds * voice.sampleRate
    return (0..<count).map { index in
        let time = Double(index)
        let fadeOut = index < fadeFrom ? 1 : Float(1 - Double(index - fadeFrom) / fadeLength)
        let sustain = interpolated(voice, at: looped(sustainStart + time * step, voice.loop))
        let handover = ramp(time, from: samples(attackHoldSeconds), over: samples(attackHandoverSeconds))
        let mixed: Float =
            note.legato
            ? ramp(time, from: 0, over: samples(releaseSeconds)) * sustain
            : ramp(time, from: 0, over: samples(attackRiseSeconds)) * (1 - handover)
                * interpolated(voice, at: looped(attackStart + time * step, voice.loop)) + handover * sustain
        return fadeOut * mixed
    }
}

/// 0 before `start`, rising linearly to 1 over `length`, then 1.
private func ramp(_ time: Double, from start: Double, over length: Double) -> Float {
    Float(min(max((time - start) / max(length, 1), 0), 1))
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
