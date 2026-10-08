import CoreGraphics
import Foundation
import Testing

@testable import ScoreKit

/// `1 2' | 3 3 |]` in 2/4 (ids n1…n4), quarter notes, with the given spans and marks, and `secondNote` added to
/// n2's fields (such as its techniques).
func phrasedScore(spans: String, marks: String = "", secondNote: String = "") throws -> Score {
    func note(_ id: String, _ start: Int, _ degree: Int, _ octave: Int, _ extra: String = "") -> String {
        """
        {"kind": "note", "id": "\(id)", "start": \(start), "duration": 480, "value": 4, "dots": 0, \
        "pitch": {"degree": \(degree), "octave": \(octave), "semitones": \(octave * 12)}\(extra)}
        """
    }
    func measure(_ index: Int, _ barline: String) -> String {
        """
        {"index": \(index), "start": \(index * 960), "duration": 960, "time": {"beats": 2, "unit": 4}, \
        "barline": "\(barline)"}
        """
    }
    let json = """
        {"irVersion": 1, "meta": {}, "header": {"key": {"tonic": "D"}}, "ticksPerQuarter": 480,
         "measures": [\(measure(0, "single")), \(measure(1, "final"))],
         "playOrder": [0, 1],
         "parts": [{"id": "solo", "role": "solo", "measures": [
            {"events": [\(note("n1", 0, 1, 0)), \(note("n2", 480, 2, 1, secondNote))], "beams": []},
            {"events": [\(note("n3", 960, 3, 0)), \(note("n4", 1440, 3, 0))], "beams": []}]}],
         "spans": [\(spans)],
         "marks": [{"kind": "tempo", "at": 0, "beat": 480, "bpm": 60}\(marks)]}
        """
    return try Score.decode(from: Data(json.utf8))
}

private struct Arc {
    let left: CGFloat
    let right: CGFloat
    let endY: CGFloat
    let rise: CGFloat
}

private func arcs(_ line: ScoreLayout.Line) -> [Arc] {
    line.items.compactMap { item in
        guard case .arc(let left, let right, let endY, let rise) = item else { return nil }
        return Arc(left: left, right: right, endY: endY, rise: rise)
    }
}

private func center(_ id: String, _ line: ScoreLayout.Line) throws -> CGPoint {
    try #require(line.items.compactMap(\.head).first { $0.id == id }).center
}

@Test func drawsASlurAboveItsNotesAndClearOfHighDots() throws {
    let score = try phrasedScore(
        spans: #"{"type": "slur", "from": "n1", "to": "n2"}, {"type": "tie", "from": "n3", "to": "n4"}"#)
    let line = try #require(ScoreLayout(score: score, width: 2000).lines.first)
    let (slur, tie) = (try #require(arcs(line).first), try #require(arcs(line).last))
    let (first, second, third) = (try center("n1", line), try center("n2", line), try center("n3", line))

    #expect(slur.left == first.x && slur.right == second.x)
    #expect(tie.endY < third.y)
    #expect(slur.endY < tie.endY)  // n2 has a high dot, so its slur sits higher than the tie over plain notes
}

@Test func splitsASlurAtALineBreak() throws {
    let score = try phrasedScore(spans: #"{"type": "slur", "from": "n2", "to": "n3"}"#)
    let lines = ScoreLayout(score: score, width: 100).lines
    try #require(lines.count == 2)
    let (first, second) = (try #require(arcs(lines[0]).first), try #require(arcs(lines[1]).first))
    let (start, end) = (try center("n2", lines[0]), try center("n3", lines[1]))

    #expect(first.left == start.x && first.right == lines[0].width)
    #expect(second.left == 0 && second.right == end.x)
    #expect([first, second].allSatisfy { $0.rise <= ($0.right - $0.left) / 4 })
}

@Test func putsABreathMarkBetweenTheNotesAroundIt() throws {
    let score = try phrasedScore(spans: "", marks: #", {"kind": "breath", "at": 480, "style": "normal"}"#)
    let line = try #require(ScoreLayout(score: score, width: 2000).lines.first)
    let breath = try #require(
        line.items.lazy.compactMap { item -> CGPoint? in
            guard case .breath(let center) = item else { return nil }
            return center
        }.first)
    let (before, after) = (try center("n1", line), try center("n2", line))

    #expect(breath.x > before.x && breath.x < after.x && breath.y < before.y)
}

@Test func makesRoomAboveTheFirstLineForAHighSlur() throws {
    let slur = #"{"type": "slur", "from": "n1", "to": "n3"}"#
    let plain = ScoreLayout(score: try phrasedScore(spans: slur), width: 2000)
    // n2 is a high note with two marks; a slur over it, split by a line break, must not leave the first line's top.
    let marked = try phrasedScore(spans: slur, secondNote: #", "techniques": [{"type": "die"}, {"type": "tr"}]"#)
    let narrow = ScoreLayout(score: marked, width: 100)
    let firstLine = try #require(narrow.lines.first)
    let first = try #require(arcs(firstLine).first)

    #expect(first.endY - first.rise >= 0)
    #expect(narrow.height / CGFloat(narrow.lines.count) > ScoreMetrics().lineHeight)
    #expect(plain.height == ScoreMetrics().lineHeight)  // one line whose slur fits needs no extra room
}

@Test func marksATripletWithAnArcAndAThreeThatASlurClears() throws {
    let score = try phrasedScore(
        spans: #"{"type": "tuplet", "actual": 3, "normal": 2, "from": "n1", "to": "n2"}, "#
            + #"{"type": "slur", "from": "n1", "to": "n2"}"#)
    let line = try #require(ScoreLayout(score: score, width: 2000).lines.first)
    let number = try #require(
        line.items.lazy.compactMap { item -> CGPoint? in
            guard case .tupletNumber("3", let center) = item else { return nil }
            return center
        }.first)
    let placed = arcs(line)
    try #require(placed.count == 2)
    let (tuplet, slur) = (placed[0], placed[1])

    #expect(number.x == (tuplet.left + tuplet.right) / 2 && number.y < tuplet.endY - tuplet.rise)
    #expect(slur.endY - slur.rise < number.y)  // the slur passes over the 3
}

@Test func ignoresASpanTypeItDoesNotDraw() throws {
    let score = try phrasedScore(spans: #"{"type": "hairpin", "direction": "cresc", "from": "n1", "to": "n2"}"#)
    let line = try #require(ScoreLayout(score: score, width: 2000).lines.first)

    #expect(score.spans.map(\.type) == [.other])
    #expect(arcs(line).isEmpty)
}
