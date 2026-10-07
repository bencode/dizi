/// One note of the demo melody, on the run's clock (seconds from the first count-in click).
public struct MelodyNote: Sendable, Equatable {
    public let time: Double
    public let duration: Double
    public let midi: Int
}

extension Run {
    /// Every note played from the run's start to the end, timed like `clicks`. Rests sound nothing.
    public func melody(_ timeline: Timeline, score: Score) -> [MelodyNote] {
        let semitones = Dictionary(
            score.parts.first { $0.role == .solo }?.measures.flatMap(\.events).compactMap(\.pitchedNote) ?? [],
            uniquingKeysWith: { first, _ in first })
        let tonic = tonicMIDI(score.header.key)
        let origin = timeline.entries[from].start
        let lead = countInLength(timeline)
        return timeline.entries[from...].compactMap { entry in
            semitones[entry.id].map { offset in
                MelodyNote(
                    time: tempo.seconds(lead + entry.start - origin), duration: tempo.seconds(entry.duration),
                    midi: tonic + offset)
            }
        }
    }
}

/// The MIDI note of an undotted `1`: the tonic in A4…G♯5, where 筒音作5 puts it on the flute in that key
/// (1=D → D5, 1=F → F5, 1=A → A4).
public func tonicMIDI(_ key: Key) -> Int {
    let letters: [String: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]
    let shift =
        switch key.accidental {
        case .sharp: 1
        case .flat: -1
        case nil: 0
        }
    let pitchClass = ((letters[key.tonic] ?? 0) + shift + 12) % 12
    return 69 + (pitchClass - 9 + 12) % 12
}

extension Event {
    fileprivate var pitchedNote: (String, Int)? {
        guard case .note(let note) = self else { return nil }
        return (note.id, note.pitch.semitones)
    }
}
