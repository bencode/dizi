import Foundation
import Testing

@testable import ScoreKit

private let rate = 44_100.0

/// A tone of `frequency` with the given strength for each harmonic (the first is the fundamental).
private func tone(_ frequency: Double, harmonics: [Double] = [1], count: Int = 4096) -> [Float] {
    (0..<count).map { index in
        let time = Double(index) / rate
        let sum = harmonics.enumerated().reduce(0.0) { sum, harmonic in
            sum + harmonic.element * sin(2 * .pi * frequency * Double(harmonic.offset + 1) * time)
        }
        return Float(0.3 * sum)
    }
}

@Test func findsThePitchOfATone() throws {
    let found = try #require(detectedFrequency(tone(440), sampleRate: rate))
    #expect(abs(found - 440) < 0.5)
}

@Test func findsTheFundamentalUnderStrongerOvertones() throws {
    // A flute with a buzzing membrane (笛膜): the second and third harmonics louder than the fundamental.
    let found = try #require(detectedFrequency(tone(587.33, harmonics: [0.4, 1, 0.8]), sampleRate: rate))
    #expect(abs(found - 587.33) < 1)
}

@Test func hearsNoPitchInSilenceOrNoise() {
    var generator = SystemRandomNumberGenerator()
    let noise = (0..<4096).map { _ in Float.random(in: -0.3...0.3, using: &generator) }

    #expect(detectedFrequency([Float](repeating: 0, count: 4096), sampleRate: rate) == nil)
    #expect(detectedFrequency(noise, sampleRate: rate) == nil)
}
