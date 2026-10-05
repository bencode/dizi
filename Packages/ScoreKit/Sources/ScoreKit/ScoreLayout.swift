import CoreGraphics

/// Every size the layout uses, derived from one font size, so a larger text or a wider screen is just a relayout.
public struct ScoreMetrics: Sendable {
    public let fontSize: CGFloat

    public init(fontSize: CGFloat = 24) {
        self.fontSize = fontSize
    }

    /// The natural width of a quarter note, and of each 增时线.
    var quarterWidth: CGFloat { fontSize * 1.25 }
    var minimumHeadWidth: CGFloat { fontSize * 0.8 }
    var digitHalfWidth: CGFloat { fontSize * 0.3 }
    var digitHeight: CGFloat { fontSize }
    var augmentationDotWidth: CGFloat { fontSize * 0.4 }
    var barGap: CGFloat { fontSize * 0.7 }
    public var lineHeight: CGFloat { fontSize * 3.2 }
    var dotGap: CGFloat { fontSize / 6 }
    var dotSpacing: CGFloat { fontSize / 4 }
    var dashWidth: CGFloat { fontSize * 0.6 }
    var underlineGap: CGFloat { fontSize / 8 }
    var underlineSpacing: CGFloat { fontSize / 5 }
}

/// Where everything of a score goes, for one screen width. Positions are in the score's own coordinates.
public struct ScoreLayout: Sendable {
    public let lines: [Line]
    public let height: CGFloat

    public struct Line: Sendable {
        /// Indices into `Score.measures`.
        public let measures: [Int]
        public let items: [Item]
        /// From the left edge to the end of the last bar line's gap.
        public let width: CGFloat
    }

    public enum Item: Sendable, Equatable {
        /// A note or rest digit centered at `center`; `degree` is 0 for a rest. A long rest repeats its 0 under
        /// the same id; the first one is the rest's position.
        case digit(id: String, start: Int, degree: Int, center: CGPoint)
        case octaveDot(noteID: String, center: CGPoint)
        /// 附点
        case augmentationDot(noteID: String, center: CGPoint)
        /// 增时线: one more beat of the note. Long rests repeat their 0 instead.
        case dash(noteID: String, center: CGPoint, width: CGFloat)
        /// 减时线 of one level, under one note or a beamed group.
        case underline(level: Int, left: CGFloat, right: CGFloat, lineY: CGFloat)
        case barline(Barline, centerX: CGFloat, top: CGFloat, bottom: CGFloat)
    }
}

/// Lays out the solo part. Lines take as many measures as fit, a section mark starts a new line,
/// and every line but the last is stretched to the full width.
public func layoutScore(_ score: Score, width: CGFloat, metrics: ScoreMetrics = ScoreMetrics()) -> ScoreLayout {
    guard let part = score.parts.first else { return ScoreLayout(lines: [], height: 0) }
    let boxes = part.measures.map { $0.events.compactMap(eventBox) }
    let sectionStarts = Set(score.marks.compactMap(\.sectionTick))
    let groups = lineGroups(
        widths: boxes.map { naturalWidth($0, metrics) + metrics.barGap },
        forcedStarts: Set(score.measures.filter { sectionStarts.contains($0.start) }.map(\.index)),
        available: width)
    let context = LineContext(score: score, part: part, boxes: boxes, metrics: metrics)
    let lines = groups.enumerated().map { row, measures in
        let natural = measures.map { naturalWidth(boxes[$0], metrics) }.reduce(0, +)
        let gaps = CGFloat(measures.count) * metrics.barGap
        let isLast = row == groups.count - 1
        let scale = isLast || natural == 0 ? 1 : max(1, (width - gaps) / natural)
        return layoutLine(measures, row: row, scale: scale, context)
    }
    return ScoreLayout(lines: lines, height: metrics.lineHeight * CGFloat(lines.count))
}

private func naturalWidth(_ boxes: [EventBox], _ metrics: ScoreMetrics) -> CGFloat {
    boxes.map { $0.naturalWidth(metrics) }.reduce(0, +)
}

private func lineGroups(widths: [CGFloat], forcedStarts: Set<Int>, available: CGFloat) -> [[Int]] {
    var groups: [[Int]] = []
    var current: [Int] = []
    var used: CGFloat = 0
    for (index, width) in widths.enumerated() {
        if !current.isEmpty && (used + width > available || forcedStarts.contains(index)) {
            groups.append(current)
            current = []
            used = 0
        }
        current.append(index)
        used += width
    }
    return current.isEmpty ? groups : groups + [current]
}

/// What every line of one layout shares.
private struct LineContext {
    let score: Score
    let part: Part
    let boxes: [[EventBox]]
    let metrics: ScoreMetrics
}

private func layoutLine(_ measures: [Int], row: Int, scale: CGFloat, _ context: LineContext) -> ScoreLayout.Line {
    let metrics = context.metrics
    let baseline = metrics.lineHeight * (CGFloat(row) + 0.5)
    var items: [ScoreLayout.Item] = []
    var cursor: CGFloat = 0
    let top = baseline - metrics.lineHeight * 0.3
    let bottom = baseline + metrics.lineHeight * 0.3
    for index in measures {
        let placed = context.boxes[index].map { box in
            defer { cursor += box.naturalWidth(metrics) * scale }
            return placeBox(box, left: cursor, scale: scale, baseline: baseline, metrics: metrics)
        }
        items += placed.flatMap(\.items)
        items += underlines(placed, beams: context.part.measures[index].beams, baseline: baseline, metrics: metrics)
        cursor += metrics.barGap / 2
        items.append(.barline(context.score.measures[index].barline, centerX: cursor, top: top, bottom: bottom))
        cursor += metrics.barGap / 2
    }
    return ScoreLayout.Line(measures: measures, items: items, width: cursor)
}

extension Mark {
    fileprivate var sectionTick: Int? {
        guard case .section(let section) = self else { return nil }
        return section.tick
    }
}
