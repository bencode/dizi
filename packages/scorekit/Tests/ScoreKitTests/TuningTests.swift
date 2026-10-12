import Foundation
import Testing

@testable import ScoreKit

@Test func readsTheTubeAsLowFiveOnADFlute() {
    let note = tunedNote(frequency: 440, flute: .keyD, tube: 5)

    #expect((note.degree, note.accidental, note.octave, note.concert) == (5, nil, -1, "A4"))
    #expect(abs(note.cents) < 0.01)
}

@Test func readsMiddleOneAndHowFarANoteIsOff() {
    #expect(tunedNote(frequency: 587.33, flute: .keyD, tube: 5).degree == 1)
    #expect(tunedNote(frequency: 587.33, flute: .keyD, tube: 5).octave == 0)
    // 450 Hz is 39 cents above A4.
    let sharp = tunedNote(frequency: 450, flute: .keyD, tube: 5)
    #expect(sharp.degree == 5)
    #expect(abs(sharp.cents - 38.9) < 0.1)
}

@Test func readsTheTubeAsLowTwoWhenFingeredAsTwo() {
    let note = tunedNote(frequency: 440, flute: .keyD, tube: 2)

    #expect((note.degree, note.octave) == (2, -1))
}

@Test func writesChromaticNotesWithSharpsAndFlatSeven() {
    // C flute 作5: 1 = C5. F♯5 is ♯4, B♭5 is ♭7.
    #expect(tunedNote(frequency: 739.99, flute: .keyC, tube: 5).accidental == .sharp)
    #expect(tunedNote(frequency: 739.99, flute: .keyC, tube: 5).degree == 4)
    #expect(tunedNote(frequency: 932.33, flute: .keyC, tube: 5).accidental == .flat)
    #expect(tunedNote(frequency: 932.33, flute: .keyC, tube: 5).degree == 7)
}
