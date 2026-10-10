import Foundation
import Testing

@testable import ScoreKit

private let rate = 1_000.0

/// A 100 Hz tone, 0.2 s long, looping its second half.
private let tone = Voice(
    samples: (0..<200).map { Float(sin(2 * Double.pi * 100 * Double($0) / rate)) }, sampleRate: rate, midi: 69,
    tuneCents: 0, loop: 100..<200)

@Test func retunesAVoiceRecordedSharp() {
    let sharp = Voice(samples: tone.samples, sampleRate: rate, midi: 69, tuneCents: 22, loop: tone.loop)

    #expect(abs(playbackStep(sharp, midi: 69, sampleRate: rate) - pow(2, -0.22 / 12)) < 1e-12)
    #expect(abs(playbackStep(tone, midi: 81, sampleRate: rate) - 2) < 1e-12)
}

@Test func placesEachNoteAtItsTimeAndSustainsItByLooping() {
    let mix = melodySamples(
        [MelodyNote(time: 0.25, duration: 0.5, midi: 69, legato: false)], voices: [tone], sampleRate: rate)
    let energy = { (range: Range<Int>) in mix[range].map { $0 * $0 }.reduce(0, +) }

    #expect(mix.count == Int(((0.25 + 0.5 + releaseSeconds) * rate).rounded(.up)))
    #expect(energy(0..<250) == 0)
    #expect(energy(250..<300) > 1)
    #expect(energy(650..<750) > 1)  // past the voice's 0.2 s: the loop keeps it sounding
    #expect(abs(mix[mix.count - 1]) < 0.05)  // faded out
}

@Test func startsATonguedNoteSoftlyInsteadOfWithAKnock() {
    // A voice at a constant level, so the output is the note's gain.
    let flat = Voice(
        samples: Array(repeating: 1, count: 200), sampleRate: rate, midi: 69, tuneCents: 0, loop: 100..<200)
    let mix = melodySamples(
        [MelodyNote(time: 0, duration: 0.5, midi: 69, legato: false)], voices: [flat], sampleRate: rate)
    let rise = Int(attackRiseSeconds * rate)

    #expect(mix[0] == 0)
    #expect(abs(mix[rise / 2] - 0.4) < 0.01)  // halfway up the rise
    #expect(abs(mix[rise * 3] - 0.8) < 0.01)  // full level
}
