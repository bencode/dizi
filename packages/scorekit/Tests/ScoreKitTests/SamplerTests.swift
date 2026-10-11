import Foundation
import Testing

@testable import ScoreKit

private let rate = 1_000.0

/// A 100 Hz tone, 0.2 s long.
private let tone = Voice(
    samples: (0..<200).map { Float(sin(2 * Double.pi * 100 * Double($0) / rate)) }, sampleRate: rate, midi: 69)

@Test func retunesAVoiceToTheNotesPitch() {
    let recordedFaster = Voice(samples: tone.samples, sampleRate: 2 * rate, midi: 69)

    #expect(abs(playbackStep(tone, midi: 81, sampleRate: rate) - 2) < 1e-12)
    #expect(abs(playbackStep(tone, midi: 66, sampleRate: rate) - pow(2, -3.0 / 12)) < 1e-12)
    #expect(abs(playbackStep(recordedFaster, midi: 69, sampleRate: rate) - 2) < 1e-12)
}

@Test func placesEachNoteAtItsTimeAndFadesItAtItsEnd() {
    let long = Voice(samples: Array(repeating: 1, count: 2_000), sampleRate: rate, midi: 69)
    let mix = melodySamples([MelodyNote(time: 0.25, duration: 0.5, midi: 69)], voices: [long], sampleRate: rate)
    let energy = { (range: Range<Int>) in mix[range].map { $0 * $0 }.reduce(0, +) }

    #expect(mix.count == Int(((0.25 + 0.5 + releaseSeconds) * rate).rounded(.up)))
    #expect(energy(0..<250) == 0)
    #expect(energy(250..<750) > 1)
    #expect(abs(mix[mix.count - 1]) < 0.05)  // faded out
}

@Test func fallsSilentWhenTheRecordingEnds() {
    // A note held past its 0.2 s recording: silence after it, not the last sample held.
    let mix = melodySamples([MelodyNote(time: 0, duration: 0.5, midi: 69)], voices: [tone], sampleRate: rate)

    #expect(mix[250..<500].allSatisfy { $0 == 0 })
}
