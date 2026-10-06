import CoreGraphics
import Testing

@testable import ScoreKit

private let slow = Tempo(bpm: 60, beat: 480)

@Test func laysTheNotesEndToEndInPlayingOrder() throws {
    let timeline = Timeline(score: try molihua())

    #expect(timeline.entries.count == 69)
    #expect(zip(timeline.entries, timeline.entries.dropFirst()).allSatisfy { $0.start + $0.duration == $1.start })
    #expect(timeline.end == 27 * 960)
}

@Test func convertsTicksAndSeconds() {
    #expect(slow.seconds(480) == 1)
    #expect(slow.ticks(0.5) == 240)
    #expect(Tempo(bpm: 120, beat: 480).seconds(960) == 1)
}

@Test func countsInOneBarThenFollowsTheNotes() throws {
    let timeline = Timeline(score: try molihua())
    let run = Run(from: 0, tempo: slow)

    #expect(run.position(at: 0, in: timeline) == .countIn(beatsLeft: 2))
    #expect(run.position(at: 1, in: timeline) == .countIn(beatsLeft: 1))
    #expect(run.position(at: 2, in: timeline) == .entry(0))
    #expect(run.position(at: 3.25, in: timeline) == .entry(1))
    #expect(run.position(at: run.length(timeline), in: timeline) == .finished)
    #expect(run.beat(at: 1, in: timeline) == nil)
    #expect(run.beat(at: 3.5, in: timeline).map { [$0.index, $0.count] } == [1, 2])
}

@Test func clicksEveryBeatAndAccentsEachBar() throws {
    let clicks = Run(from: 0, tempo: slow).clicks(Timeline(score: try molihua()))

    #expect(
        clicks.prefix(5) == [
            Click(time: 0, accent: true), Click(time: 1, accent: false),
            Click(time: 2, accent: true), Click(time: 3, accent: false), Click(time: 4, accent: true),
        ])
    #expect(clicks.count == 2 + 27 * 2)
}

@Test func startsFromATappedNote() throws {
    let score = try molihua()
    let timeline = Timeline(score: score)
    let layout = ScoreLayout(score: score, width: 360)
    let center = try #require(layout.lines[0].items.compactMap(\.head).first { $0.id == "n4" }?.center)

    let tapped = try #require(layout.note(near: CGPoint(x: center.x + 3, y: center.y + 10)))
    let from = try #require(timeline.firstEntry(of: tapped))
    let run = Run(from: from, tempo: slow)

    #expect(tapped == "n4")
    #expect(run.position(at: 2, in: timeline) == .entry(from))
    #expect(run.clicks(timeline).dropFirst(2).first == Click(time: 2, accent: true))
}
