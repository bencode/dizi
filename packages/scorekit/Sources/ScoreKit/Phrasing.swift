import CoreGraphics

/// The lines with each slur's and tie's arcs, and each breath mark, added to the lines they fall on.
func phrased(_ lines: [ScoreLayout.Line], score: Score, metrics: ScoreMetrics) -> [ScoreLayout.Line] {
    let arcs = score.spans.flatMap { arcs(of: $0, on: lines, metrics: metrics) }
    let breaths = score.marks.compactMap { mark -> (row: Int, item: ScoreLayout.Item)? in
        guard case .breath(let breath) = mark else { return nil }
        return breathMark(at: breath.tick, on: lines, metrics: metrics)
    }
    let added = Dictionary(grouping: arcs + breaths, by: \.row).mapValues { $0.map(\.item) }
    return lines.enumerated().map { row, line in
        ScoreLayout.Line(
            measures: line.measures, items: line.items + (added[row] ?? []), anchors: line.anchors,
            endTick: line.endTick, width: line.width)
    }
}

/// Where a note's digit is: its line and its center.
private func digit(_ id: String, on lines: [ScoreLayout.Line]) -> (row: Int, center: CGPoint)? {
    lines.enumerated().lazy.compactMap { row, line in
        line.items.lazy.compactMap(\.head).first { $0.id == id }.map { (row, $0.center) }
    }.first
}

/// One arc per line the span crosses: from its first note to the line's end, across whole lines, and from the
/// line's start to its last note.
private func arcs(of span: Span, on lines: [ScoreLayout.Line], metrics: ScoreMetrics) -> [(
    row: Int, item: ScoreLayout.Item
)] {
    guard let first = digit(span.first, on: lines), let last = digit(span.last, on: lines), first.row <= last.row
    else { return [] }
    let edge = metrics.digitHalfWidth
    return (first.row...last.row).compactMap { row in
        let line = lines[row]
        let left = row == first.row ? first.center.x : edge
        let right = row == last.row ? last.center.x : line.width - edge
        guard right > left else { return nil }
        return (row, .arc(left: left, right: right, endY: clearance(line, left...right, metrics) - metrics.dotGap))
    }
}

/// The highest point of the digits and high-octave dots between `span`: an arc there clears them.
private func clearance(_ line: ScoreLayout.Line, _ span: ClosedRange<CGFloat>, _ metrics: ScoreMetrics) -> CGFloat {
    let reach = metrics.digitHalfWidth
    let tops = line.items.compactMap { item -> CGFloat? in
        switch item {
        case .note(_, _, _, let center) where span.contains(center.x):
            center.y - metrics.digitHeight / 2
        case .octaveDot(_, let center) where (span.lowerBound - reach...span.upperBound + reach).contains(center.x):
            center.y - metrics.dotSpacing / 2
        default: nil
        }
    }
    let baseline = line.items.compactMap(\.head).first?.center.y ?? 0
    return tops.min() ?? baseline - metrics.digitHeight / 2
}

/// A breath mark after the note that ends at `tick`: halfway to the next digit on its line, or at the line's end.
private func breathMark(at tick: Int, on lines: [ScoreLayout.Line], metrics: ScoreMetrics) -> (
    row: Int, item: ScoreLayout.Item
)? {
    lines.enumerated().lazy.compactMap { row, line -> (row: Int, item: ScoreLayout.Item)? in
        guard let before = line.anchors.lastIndex(where: { $0.tick < tick }),
            tick <= line.endTick,
            let baseline = line.items.compactMap(\.head).first?.center.y
        else { return nil }
        let next = line.anchors.indices.contains(before + 1) ? line.anchors[before + 1].position : line.width
        let centerX = (line.anchors[before].position + next) / 2
        return (row, .breath(center: CGPoint(x: centerX, y: baseline - metrics.lineHeight * 0.3)))
    }.first
}
