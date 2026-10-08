import CoreGraphics

/// An item and the line it goes on.
private typealias Placed = (row: Int, item: ScoreLayout.Item)

/// The lines with each triplet's arc and 3, each slur's and tie's arcs, and each breath mark, added to the lines
/// they fall on. Triplets go first, so a slur over one clears its 3.
func phrased(_ lines: [ScoreLayout.Line], score: Score, metrics: ScoreMetrics) -> [ScoreLayout.Line] {
    let tuplets = score.spans.filter { $0.type == .tuplet }.flatMap { span in
        let pieces = arcs(of: span, on: lines, metrics: metrics)
        return pieces + pieces.prefix(1).compactMap { piece in tupletNumber(over: piece, metrics: metrics) }
    }
    let withTuplets = adding(tuplets, to: lines)
    let slurs = score.spans.filter { $0.type == .slur || $0.type == .tie }.flatMap { span in
        arcs(of: span, on: withTuplets, metrics: metrics)
    }
    let breaths = score.marks.compactMap { mark -> Placed? in
        guard case .breath(let breath) = mark else { return nil }
        return breathMark(at: breath.tick, on: lines, metrics: metrics)
    }
    return adding(slurs + breaths, to: withTuplets)
}

private func adding(_ placed: [Placed], to lines: [ScoreLayout.Line]) -> [ScoreLayout.Line] {
    let added = Dictionary(grouping: placed, by: \.row).mapValues { $0.map(\.item) }
    return lines.enumerated().map { row, line in
        ScoreLayout.Line(
            measures: line.measures, items: line.items + (added[row] ?? []), anchors: line.anchors,
            endTick: line.endTick, width: line.width)
    }
}

/// A triplet's 3, just above the middle of its arc.
private func tupletNumber(over piece: Placed, metrics: ScoreMetrics) -> Placed? {
    guard case .arc(let left, let right, let endY, let rise) = piece.item else { return nil }
    let center = CGPoint(x: (left + right) / 2, y: endY - rise - metrics.fontSize * 0.2)
    return (piece.row, .tupletNumber(label: "3", center: center))
}

/// Where a note's digit is: its line and its center.
private func digit(_ id: String, on lines: [ScoreLayout.Line]) -> (row: Int, center: CGPoint)? {
    lines.enumerated().lazy.compactMap { row, line in
        line.items.lazy.compactMap(\.head).first { $0.id == id }.map { (row, $0.center) }
    }.first
}

/// One arc per line the span crosses: from its first note to the line's end, across whole lines, and from the
/// line's start to its last note.
private func arcs(of span: Span, on lines: [ScoreLayout.Line], metrics: ScoreMetrics) -> [Placed] {
    guard let first = digit(span.first, on: lines), let last = digit(span.last, on: lines), first.row <= last.row
    else { return [] }
    return (first.row...last.row).compactMap { row in
        let line = lines[row]
        // A piece that continues from the line before or onto the next runs to that edge.
        let left = row == first.row ? first.center.x : 0
        let right = row == last.row ? last.center.x : line.width
        guard right > left else { return nil }
        // A short piece stays shallow, so it reads as part of an arc rather than as a mark.
        let width = right - left
        let rise = min(max(width * 0.12, metrics.fontSize * 0.15), metrics.fontSize * 0.4, width * 0.25)
        let endY = clearance(line, left...right, metrics) - metrics.dotGap
        return (row, .arc(left: left, right: right, endY: endY, rise: rise))
    }
}

/// The highest point of what sits above the notes between `span` (digits, high-octave dots, technique marks,
/// graces): an arc there clears them.
private func clearance(_ line: ScoreLayout.Line, _ span: ClosedRange<CGFloat>, _ metrics: ScoreMetrics) -> CGFloat {
    let reach = metrics.digitHalfWidth
    let tops = line.items.compactMap { item -> CGFloat? in
        switch item {
        case .note(_, _, _, let center) where span.contains(center.x):
            center.y - metrics.digitHeight / 2
        case .octaveDot(_, let center) where (span.lowerBound - reach...span.upperBound + reach).contains(center.x):
            center.y - metrics.dotSpacing / 2
        case .graceDot(let center) where span.contains(center.x):
            center.y - metrics.dotSpacing / 2
        case .technique(_, _, let center) where span.contains(center.x):
            center.y - metrics.markHeight / 2
        case .grace(_, _, let center) where span.contains(center.x):
            center.y - metrics.digitHeight * metrics.graceScale / 2
        case .tupletNumber(_, let center) where span.contains(center.x):
            center.y - metrics.fontSize * 0.3
        case .arc(let left, let right, let endY, let rise) where span.overlaps(left...right):
            endY - rise
        default: nil
        }
    }
    let baseline = line.items.compactMap(\.head).first?.center.y ?? 0
    return tops.min() ?? baseline - metrics.digitHeight / 2
}

/// A breath mark after the note that ends at `tick`: halfway to the next digit on its line, or at the line's end.
private func breathMark(at tick: Int, on lines: [ScoreLayout.Line], metrics: ScoreMetrics) -> Placed? {
    lines.enumerated().lazy.compactMap { row, line -> Placed? in
        guard let before = line.anchors.lastIndex(where: { $0.tick < tick }),
            tick <= line.endTick,
            let baseline = line.items.compactMap(\.head).first?.center.y
        else { return nil }
        let next = line.anchors.indices.contains(before + 1) ? line.anchors[before + 1].position : line.width
        let centerX = (line.anchors[before].position + next) / 2
        return (row, .breath(center: CGPoint(x: centerX, y: baseline - metrics.lineHeight * 0.3)))
    }.first
}
