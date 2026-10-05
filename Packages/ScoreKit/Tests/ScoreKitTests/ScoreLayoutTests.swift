import CoreGraphics
import Foundation
import Testing

@testable import ScoreKit

/// docs/examples/molihua.ir.json, the fixture the spec publishes and the app bundles.
private func molihua() throws -> Score {
    let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // ScoreKitTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // ScoreKit
        .deletingLastPathComponent()  // Packages
        .deletingLastPathComponent()
    let url = repository.appending(path: "docs/examples/molihua.ir.json")
    return try Score.decode(from: Data(contentsOf: url))
}

private let wide: CGFloat = 1000

private func digits(_ line: ScoreLayout.Line) -> [String] {
    line.items.compactMap { item in
        guard case .digit(let id, _, _, _) = item else { return nil }
        return id
    }
}

@Test func decodesTheSpecExample() throws {
    let score = try molihua()

    #expect(score.meta.title == "茉莉花")
    #expect(score.header.key == Key(tonic: "F", accidental: nil))
    #expect(score.measures.allSatisfy { $0.time == .meter(beats: 2, unit: 4) })
    #expect(score.parts.first?.measures.count == score.measures.count)
}

@Test func breaksLinesWhereTheScoreDoes() throws {
    let layout = layoutScore(try molihua(), width: wide)

    #expect(layout.lines.prefix(2).map(\.measures) == [[0, 1], [2, 3]])
    #expect(digits(layout.lines[0]) == ["n1", "n2", "n3", "n4", "n5", "n6", "n7"])
    guard case .barline(let last, _, _, _) = layout.lines.last?.items.last else {
        Issue.record("the last line does not end with a bar line")
        return
    }
    #expect(last == .final)
}

@Test func putsOneDotAboveAHighNote() throws {
    let items = layoutScore(try molihua(), width: wide).lines[0].items
    let digit = items.first { item in
        if case .digit("n5", _, _, _) = item { return true }
        return false
    }
    let dots = items.compactMap { item -> CGPoint? in
        guard case .octaveDot("n5", let center) = item else { return nil }
        return center
    }

    guard case .digit(_, _, _, let center) = digit else {
        Issue.record("no digit for n5")
        return
    }
    #expect(dots.count == 1)
    #expect(dots.allSatisfy { $0.y < center.y && $0.x == center.x })
}

@Test func wrapsAtABarLineWhenTooNarrow() throws {
    let metrics = ScoreMetrics()
    let oneMeasure = metrics.slotWidth * 4 + metrics.barGap

    let layout = layoutScore(try molihua(), width: oneMeasure, metrics: metrics)

    #expect(layout.lines.prefix(4).map(\.measures) == [[0], [1], [2], [3]])
}

@Test func followsAHalfNoteWithOneDash() throws {
    let secondLine = layoutScore(try molihua(), width: wide).lines[1].items
    let dashes = secondLine.filter { item in
        if case .dash("n11", _, _) = item { return true }
        return false
    }

    #expect(dashes.count == 1)
}
