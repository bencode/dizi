import CoreGraphics
import Foundation
import Testing

@testable import ScoreKit

/// One 2/4 measure: `n1` with the given extra note fields (techniques, graces), octave, and accidental (`sign`),
/// then `n2`.
private func ornamented(_ extra: String = "", octave: Int = 0, sign: String = "", spans: String = "") throws -> Score {
    let json = """
        {"irVersion": 1, "meta": {}, "header": {"key": {"tonic": "D"}}, "ticksPerQuarter": 480,
         "measures": [{"index": 0, "start": 0, "duration": 960, "time": {"beats": 2, "unit": 4}, "barline": "final"}],
         "playOrder": [0],
         "parts": [{"id": "solo", "role": "solo", "measures": [{"events": [
            {"kind": "note", "id": "n1", "start": 0, "duration": 480, "value": 4, "dots": 0,
             "pitch": {"degree": 5, \(sign) "octave": \(octave), "semitones": 7}\(extra)},
            {"kind": "note", "id": "n2", "start": 480, "duration": 480, "value": 4, "dots": 0,
             "pitch": {"degree": 3, "octave": 0, "semitones": 4}}], "beams": []}]}],
         "spans": [\(spans)], "marks": []}
        """
    return try Score.decode(from: Data(json.utf8))
}

private func items(_ score: Score) throws -> [ScoreLayout.Item] {
    try #require(ScoreLayout(score: score, width: 2000).lines.first).items
}

private func digit(_ id: String, _ items: [ScoreLayout.Item]) throws -> CGPoint {
    try #require(items.compactMap(\.head).first { $0.id == id }).center
}

private func marks(_ items: [ScoreLayout.Item]) -> [(Technique, CGPoint)] {
    items.compactMap { item in
        guard case .technique(_, let technique, let center) = item else { return nil }
        return (technique, center)
    }
}

@Test func stacksMarksAboveTheNoteAndItsHighDot() throws {
    let laid = try items(ornamented(#", "techniques": [{"type": "die"}, {"type": "tr"}]"#, octave: 1))
    let note = try digit("n1", laid)
    let highDot = try #require(
        laid.lazy.compactMap { item -> CGPoint? in
            guard case .octaveDot("n1", let center) = item else { return nil }
            return center
        }.first)
    let placed = marks(laid)

    #expect(placed.map(\.0) == [.die, .trill])
    #expect(placed.allSatisfy { $0.1.x == note.x })
    #expect(placed[0].1.y < highDot.y && placed[1].1.y < placed[0].1.y)
}

@Test func putsASlideUpBeforeTheDigitAndASlideDownAfterIt() throws {
    let rising = try items(ornamented(#", "techniques": [{"type": "slide", "direction": "up"}]"#))
    let falling = try items(ornamented(#", "techniques": [{"type": "slide", "direction": "down"}]"#))
    let (risingDigit, fallingDigit) = (try digit("n1", rising), try digit("n1", falling))

    #expect(try #require(marks(rising).first).1.x < risingDigit.x)
    #expect(try #require(marks(falling).first).1.x > fallingDigit.x)
}

@Test func writesAGraceSmallBeforeItsNoteAndMakesRoomForIt() throws {
    let plain = try items(ornamented())
    let graced = try items(
        ornamented(#", "graces": [{"position": "before", "pitches": [{"degree": 6, "octave": 0, "semitones": 9}]}]"#))
    let grace = try #require(
        graced.lazy.compactMap { item -> CGPoint? in
            guard case .grace("n1", 6, let center) = item else { return nil }
            return center
        }.first)
    let note = try digit("n1", graced)

    #expect(grace.x < note.x && grace.y < note.y)
    #expect(try digit("n2", graced).x > (try digit("n2", plain)).x)  // the grace's room pushes what follows
}

@Test func writesASharpBeforeTheDigit() throws {
    let laid = try items(ornamented(sign: #""accidental": "sharp","#))
    let sign = try #require(
        laid.lazy.compactMap { item -> CGPoint? in
            guard case .accidental("n1", true, let center) = item else { return nil }
            return center
        }.first)

    #expect(sign.x < (try digit("n1", laid)).x)
}

@Test func passesASlurOverATechniqueMark() throws {
    let laid = try items(
        ornamented(
            #", "techniques": [{"type": "bo", "direction": "up"}]"#,
            spans: #"{"type": "slur", "from": "n1", "to": "n2"}"#))
    let mark = try #require(marks(laid).first).1
    let arcY = try #require(
        laid.lazy.compactMap { item -> CGFloat? in
            guard case .arc(_, _, let endY, _) = item else { return nil }
            return endY
        }.first)

    #expect(arcY < mark.y)
}

@Test func decodesUnknownTechniquesAndMissingLists() throws {
    let score = try ornamented(#", "techniques": [{"type": "future-technique"}]"#)
    let notes = score.parts[0].measures[0].events.compactMap { event -> Note? in
        guard case .note(let note) = event else { return nil }
        return note
    }

    #expect(notes[0].techniques == [.unknown])
    #expect(notes[1].techniques.isEmpty && notes[1].graces.isEmpty)
}

@Test func writesAGracesSharpBeforeItsDigit() throws {
    let grace = { (sign: String) in
        #", "graces": [{"position": "before", "pitches": [{"degree": 4, \#(sign) "octave": 0, "semitones": 6}]}]"#
    }
    let sharp = try items(ornamented(grace(#""accidental": "sharp","#)))
    let natural = try items(ornamented(grace("")))
    let sign = try #require(
        sharp.lazy.compactMap { item -> CGPoint? in
            guard case .accidental("n1", true, let center) = item else { return nil }
            return center
        }.first)
    let graceDigit = try #require(
        sharp.lazy.compactMap { item -> CGPoint? in
            guard case .grace("n1", 4, let center) = item else { return nil }
            return center
        }.first)
    let (wider, plain) = (try digit("n2", sharp), try digit("n2", natural))

    #expect(sign.x < graceDigit.x)
    #expect(wider.x > plain.x)  // the sign takes room
}
