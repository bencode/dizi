import CoreGraphics
import Foundation
import Testing

@testable import ScoreKit

/// docs/examples/molihua.ir.json, the fixture the spec publishes and the app bundles.
private func molihuaURL() -> URL {
    let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // ScoreKitTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // ScoreKit
        .deletingLastPathComponent()  // Packages
        .deletingLastPathComponent()
    return repository.appending(path: "docs/examples/molihua.ir.json")
}

/// Shared with the other test files.
func molihua() throws -> Score {
    try Score.decode(from: Data(contentsOf: molihuaURL()))
}

/// `5. 3_ | 【二】 5 - | 1 - |]` in 2/4: a dotted quarter, a lone eighth, and a section on measure 2.
private func sectioned() throws -> Score {
    func note(_ id: String, _ start: Int, _ value: Int, _ dots: Int, _ degree: Int) -> String {
        let duration = 1920 / value * ((1 << (dots + 1)) - 1) / (1 << dots)
        return """
            {"kind": "note", "id": "\(id)", "start": \(start), "duration": \(duration), "value": \(value), \
            "dots": \(dots), "pitch": {"degree": \(degree), "octave": 0, "semitones": 0}}
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
         "measures": [\(measure(0, "single")), \(measure(1, "single")), \(measure(2, "final"))],
         "playOrder": [0, 1, 2],
         "parts": [{"id": "solo", "role": "solo", "measures": [
            {"events": [\(note("n1", 0, 4, 1, 5)), \(note("n2", 720, 8, 0, 3))], "beams": []},
            {"events": [\(note("n3", 960, 2, 0, 5))], "beams": []},
            {"events": [\(note("n4", 1920, 2, 0, 1))], "beams": []}]}],
         "spans": [],
         "marks": [{"kind": "section", "at": 960, "label": "【二】"}]}
        """
    return try Score.decode(from: Data(json.utf8))
}

private let phone: CGFloat = 360
private let wide: CGFloat = 2000

private func digitCenter(_ id: String, in items: [ScoreLayout.Item]) -> CGPoint? {
    items.lazy.compactMap { item -> CGPoint? in
        switch item {
        case .note(id, _, _, let center), .rest(id, _, let center): center
        default: nil
        }
    }.first
}

private func levelOneUnderlines(in items: [ScoreLayout.Item]) -> [ClosedRange<CGFloat>] {
    items.compactMap { item in
        guard case .underline(1, let left, let right, _) = item else { return nil }
        return left...right
    }
}

@Test func decodesTheSpecExample() throws {
    let score = try molihua()

    #expect(score.meta.title == "茉莉花")
    #expect(score.header.key == Key(tonic: "F", accidental: nil))
    #expect(score.measures.allSatisfy { $0.time == .meter(beats: 2, unit: 4) })
    #expect(score.parts.first?.measures.count == score.measures.count)
}

@Test func stretchesEveryLineButTheLastToTheFullWidth() throws {
    let lines = ScoreLayout(score: try molihua(), width: phone).lines

    #expect(lines.count > 1)
    #expect(lines.dropLast().allSatisfy { abs($0.width - phone) < 0.001 })
    #expect(lines.last.map { $0.width < phone } == true)
}

@Test func startsALineAtASection() throws {
    let lines = ScoreLayout(score: try sectioned(), width: wide).lines

    #expect(lines.map(\.measures) == [[0], [1, 2]])
}

@Test func leavesTheLastLineOfASectionUnstretched() throws {
    let lines = ScoreLayout(score: try sectioned(), width: wide).lines

    #expect(lines[0].width < wide / 2)  // the line before 【二】 keeps its natural width
}

@Test func labelsASectionAtTheStartOfItsLine() throws {
    let line = ScoreLayout(score: try sectioned(), width: wide).lines[1]
    let label = try #require(
        line.items.lazy.compactMap { item -> CGPoint? in
            guard case .section("【二】", let origin) = item else { return nil }
            return origin
        }.first)
    let firstDigit = try #require(line.items.compactMap(\.head).first).center

    #expect(label.x == 0 && label.y < firstDigit.y)
}

@Test func wrapsAtABarLineWhenTooNarrow() throws {
    let metrics = ScoreMetrics()

    let lines = ScoreLayout(score: try molihua(), width: metrics.quarterWidth * 2, metrics: metrics).lines

    #expect(lines.prefix(4).map(\.measures) == [[0], [1], [2], [3]])
}

@Test func putsOneDotAboveAHighNote() throws {
    let items = ScoreLayout(score: try molihua(), width: wide).lines[0].items
    let dots = items.compactMap { item -> CGPoint? in
        guard case .octaveDot("n5", let center) = item else { return nil }
        return center
    }
    let digit = try #require(digitCenter("n5", in: items))

    #expect(dots.count == 1)
    #expect(dots.allSatisfy { $0.y < digit.y && $0.x == digit.x })
}

@Test func joinsBeamedEighthsUnderOneLine() throws {
    let items = ScoreLayout(score: try molihua(), width: wide).lines[0].items
    let quarter = try #require(digitCenter("n1", in: items))
    let first = try #require(digitCenter("n2", in: items))
    let second = try #require(digitCenter("n3", in: items))

    let spanning = levelOneUnderlines(in: items).filter { $0.contains(first.x) || $0.contains(second.x) }
    #expect(spanning.count == 1)
    #expect(spanning.allSatisfy { $0.contains(first.x) && $0.contains(second.x) })
    #expect(!levelOneUnderlines(in: items).contains { $0.contains(quarter.x) })
}

@Test func underlinesALoneEighthAndDotsADottedQuarter() throws {
    let items = ScoreLayout(score: try sectioned(), width: wide).lines[0].items
    let dotted = try #require(digitCenter("n1", in: items))
    let eighth = try #require(digitCenter("n2", in: items))
    let dots = items.compactMap { item -> CGPoint? in
        guard case .augmentationDot("n1", let center) = item else { return nil }
        return center
    }

    #expect(levelOneUnderlines(in: items).count == 1)
    #expect(levelOneUnderlines(in: items).first?.contains(eighth.x) == true)
    #expect(dots.count == 1)
    #expect(dots.allSatisfy { $0.x > dotted.x && $0.x < eighth.x })
}

@Test func followsAHalfNoteWithOneDash() throws {
    let items = ScoreLayout(score: try molihua(), width: wide).lines.flatMap(\.items)
    let dashes = items.filter { item in
        if case .dash("n11", _, _) = item { return true }
        return false
    }

    #expect(dashes.count == 1)
}

@Test func scalesWithTheFontSize() throws {
    let score = try molihua()
    let small = ScoreLayout(score: score, width: phone, metrics: ScoreMetrics(fontSize: 20))
    let large = ScoreLayout(score: score, width: phone * 2, metrics: ScoreMetrics(fontSize: 40))

    #expect(large.height == small.height * 2)
    #expect(large.lines.map(\.measures) == small.lines.map(\.measures))
    let smallDigit = try #require(digitCenter("n5", in: small.lines[0].items))
    let largeDigit = try #require(digitCenter("n5", in: large.lines[0].items))
    #expect(abs(largeDigit.x - smallDigit.x * 2) < 0.001)
}

@Test func survivesARepeatedIDInsteadOfCrashing() throws {
    let json = try String(contentsOf: molihuaURL(), encoding: .utf8).replacingOccurrences(of: "\"n3\"", with: "\"n2\"")
    let score = try Score.decode(from: Data(json.utf8))

    #expect(!ScoreLayout(score: score, width: phone).lines.isEmpty)
}
