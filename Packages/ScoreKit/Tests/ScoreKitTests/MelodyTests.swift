import Testing

@testable import ScoreKit

@Test(arguments: [
    ("C", nil, 72), ("D", nil, 74), ("F", nil, 77), ("G", nil, 79), ("A", nil, 69),
    ("B", Accidental.flat, 70), ("G", Accidental.sharp, 80),
])
func placesTheTonicWhereTheFluteFingeringPutsIt(_ tonic: String, _ accidental: Accidental?, _ midi: Int) {
    #expect(tonicMIDI(Key(tonic: tonic, accidental: accidental)) == midi)
}

@Test func playsEveryNoteOnTheClickClock() throws {
    let score = try molihua()
    let timeline = Timeline(score: score)
    let run = Run(from: 0, tempo: Tempo(bpm: 60, beat: 480))
    let melody = run.melody(timeline, score: score)

    #expect(melody.count == 69)
    #expect(melody.first == MelodyNote(time: 2, duration: 1, midi: 81))  // 3 in 1=F is A5, after a 2-beat count-in
    #expect(melody.dropFirst().first == MelodyNote(time: 3, duration: 0.5, midi: 81))
}

@Test func startsTheMelodyFromTheRunsStart() throws {
    let score = try molihua()
    let timeline = Timeline(score: score)
    let from = try #require(timeline.firstEntry(of: "n4"))
    let melody = Run(from: from, tempo: Tempo(bpm: 60, beat: 480)).melody(timeline, score: score)

    #expect(melody.count == 69 - from)
    #expect(melody.first?.time == 2)
}
