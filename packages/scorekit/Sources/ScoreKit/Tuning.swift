import Foundation

/// A dizi by its key, and the concert pitch of its 筒音 (all holes closed) as a MIDI note.
public enum Flute: String, CaseIterable, Sendable {
    case bigG, bigA, bigBFlat, keyC, keyD, keyE, keyF, keyG

    public var tube: Int {
        switch self {
        case .bigG: 62  // D4
        case .bigA: 64  // E4
        case .bigBFlat: 65  // F4
        case .keyC: 67  // G4
        case .keyD: 69  // A4
        case .keyE: 71  // B4
        case .keyF: 72  // C5
        case .keyG: 74  // D5
        }
    }
}

/// A sounding note as the player reads it on that flute: a jianpu digit with its accidental and octave (0 = middle),
/// its concert name, and how far it is from in tune.
public struct TunedNote: Sendable, Equatable {
    public let degree: Int
    public let accidental: Accidental?
    public let octave: Int
    /// Like "A4", for a tuner that tunes to A4 = 440 Hz.
    public let concert: String
    /// −50…+50: above or below the nearest equal-tempered note.
    public let cents: Double
}

/// The note at `frequency` on `flute`, fingered with the 筒音 as low `tube` (5 for 全按作5, 2 for 全按作2).
public func tunedNote(frequency: Double, flute: Flute, tube: Int) -> TunedNote {
    let exact = 69 + 12 * log2(frequency / 440)
    let midi = Int(exact.rounded())
    // Middle 1 sits an octave above the 筒音's degree, so the 筒音 reads low `tube`.
    let tonic = flute.tube + 12 - majorScale[tube - 1]
    let (octave, step) = (midi - tonic).quotientAndRemainder(dividingBy: 12)
    let (wrappedOctave, wrappedStep) = step < 0 ? (octave - 1, step + 12) : (octave, step)
    let (degree, accidental) = jianpu[wrappedStep]
    return TunedNote(
        degree: degree, accidental: accidental, octave: wrappedOctave,
        concert: "\(concertNames[((midi % 12) + 12) % 12])\(midi / 12 - 1)", cents: (exact - Double(midi)) * 100)
}

/// Semitones above 1 of the degrees 1–7.
private let majorScale = [0, 2, 4, 5, 7, 9, 11]

/// Each semitone above 1 as the player writes it: sharps, except ♭7.
private let jianpu: [(Int, Accidental?)] = [
    (1, nil), (1, .sharp), (2, nil), (2, .sharp), (3, nil), (4, nil), (4, .sharp), (5, nil), (5, .sharp), (6, nil),
    (7, .flat), (7, nil),
]

private let concertNames = ["C", "C♯", "D", "E♭", "E", "F", "F♯", "G", "A♭", "A", "B♭", "B"]
