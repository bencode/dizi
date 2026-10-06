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
    #expect(run.position(at: 2, in: timeline) == .entry(0, progress: 0))
    #expect(run.position(at: 3.25, in: timeline) == .entry(1, progress: 0.5))
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
    #expect(run.position(at: 2, in: timeline) == .entry(from, progress: 0))
    #expect(run.clicks(timeline).dropFirst(2).first == Click(time: 2, accent: true))
}

@Test func reachesEachDigitWhenItsNoteStarts() throws {
    let layout = ScoreLayout(score: try molihua(), width: 360)
    let heads = layout.lines[0].items.compactMap(\.head)

    #expect(
        heads.allSatisfy { head in
            layout.cursor(at: head.id, progress: 0).map { abs($0.x - head.center.x) < 0.001 } == true
        })
}

@Test func movesForwardSmoothlyAcrossABarLine() throws {
    let layout = ScoreLayout(score: try molihua(), width: 360)
    let samples = layout.lines[0].anchors.flatMap { anchor in
        stride(from: 0.0, to: 1.0, by: 0.1).compactMap { layout.cursor(at: anchor.id, progress: $0)?.x }
    }
    // n3 is the last eighth of measure 1; n4 the first of measure 2. Both last 240 ticks.
    let step = 0.01
    let before =
        try #require(layout.cursor(at: "n3", progress: 1)).x
        - (try #require(layout.cursor(at: "n3", progress: 1 - step))).x
    let after =
        try #require(layout.cursor(at: "n4", progress: step)).x - (try #require(layout.cursor(at: "n4", progress: 0))).x

    #expect(zip(samples, samples.dropFirst()).allSatisfy { $0 <= $1 })
    #expect(abs(after / before - 1) < 0.05)
}

@Test func reachesTheLineEndWithItsLastNote() throws {
    let layout = ScoreLayout(score: try molihua(), width: 360)
    let line = layout.lines[0]
    let last = try #require(line.anchors.last)

    #expect(layout.cursor(at: last.id, progress: 1).map { abs($0.x - line.width) < 0.001 } == true)
}
