import CoreGraphics
import Foundation
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

/// `5 | 1 2 | 3 - |]` in 2/4: a one-beat pickup, then two full bars.
private func pickup() throws -> Score {
    func note(_ id: String, _ start: Int, _ value: Int = 4) -> String {
        """
        {"kind": "note", "id": "\(id)", "start": \(start), "duration": \(1920 / value), "value": \(value), "dots": 0, \
        "pitch": {"degree": 1, "octave": 0, "semitones": 0}}
        """
    }
    let json = """
        {"irVersion": 1, "meta": {}, "header": {"key": {"tonic": "D"}}, "ticksPerQuarter": 480,
         "measures": [
            {"index": 0, "start": 0, "duration": 480, "time": {"beats": 2, "unit": 4}, "barline": "single"},
            {"index": 1, "start": 480, "duration": 960, "time": {"beats": 2, "unit": 4}, "barline": "single"},
            {"index": 2, "start": 1440, "duration": 960, "time": {"beats": 2, "unit": 4}, "barline": "final"}],
         "playOrder": [0, 1, 2],
         "parts": [{"id": "solo", "role": "solo", "measures": [
            {"events": [\(note("p", 0))], "beams": []},
            {"events": [\(note("a", 480)), \(note("b", 960))], "beams": []},
            {"events": [\(note("c", 1440, 2))], "beams": []}]}],
         "spans": [], "marks": []}
        """
    return try Score.decode(from: Data(json.utf8))
}

@Test func countsAFullBarAndAPickupAsTheBarsLastBeat() throws {
    let timeline = Timeline(score: try pickup())
    let run = Run(from: 0, tempo: slow)

    #expect(run.countInLength(timeline) == 960)
    #expect(
        run.clicks(timeline).prefix(4) == [
            Click(time: 0, accent: true), Click(time: 1, accent: false),
            Click(time: 2, accent: false), Click(time: 3, accent: true),
        ])
    #expect(run.beat(at: 2.5, in: timeline).map { [$0.index, $0.count] } == [1, 2])
}

/// `|: 1 - | [1.] 2 - :| [2.] 3 - ||` in 2/4: a repeat with two endings.
func repeatedScore() throws -> Score {
    func measure(_ index: Int, _ extra: String) -> String {
        """
        {"index": \(index), "start": \(index * 960), "duration": 960, "time": {"beats": 2, "unit": 4}, \
        "barline": "\(index == 2 ? "double" : "single")"\(extra)}
        """
    }
    func half(_ id: String, _ start: Int, _ degree: Int) -> String {
        """
        {"events": [{"kind": "note", "id": "\(id)", "start": \(start), "duration": 960, "value": 2, "dots": 0, \
        "pitch": {"degree": \(degree), "octave": 0, "semitones": 0}}], "beams": []}
        """
    }
    let json = """
        {"irVersion": 1, "meta": {}, "header": {"key": {"tonic": "D"}}, "ticksPerQuarter": 480,
         "measures": [\(measure(0, ", \"repeatStart\": true")), \(measure(1, ", \"repeatEnd\": true, \"volta\": [1]")),
                      \(measure(2, ", \"volta\": [2]"))],
         "playOrder": [0, 1, 0, 2],
         "parts": [{"id": "solo", "role": "solo", "measures": [
            \(half("a", 0, 1)), \(half("b", 960, 2)), \(half("c", 1920, 3))]}],
         "spans": [], "marks": []}
        """
    return try Score.decode(from: Data(json.utf8))
}

@Test func followsTheRepeatAndItsEndings() throws {
    let timeline = Timeline(score: try repeatedScore())

    #expect(timeline.entries.map(\.id) == ["a", "b", "a", "c"])
    #expect(timeline.entries.map(\.start) == [0, 960, 1920, 2880])
}

@Test func marksRepeatsAndEndingsOnTheScore() throws {
    let items = ScoreLayout(score: try repeatedScore(), width: 2000).lines.flatMap(\.items)
    let dots = items.filter { item in
        if case .repeatDots = item { return true }
        return false
    }
    let endings = items.compactMap { item -> String? in
        guard case .ending(let label, _) = item else { return nil }
        return label
    }

    #expect(dots.count == 2)
    #expect(endings == ["1.", "2."])
}
