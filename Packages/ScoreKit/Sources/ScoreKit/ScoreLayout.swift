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
        /// Each note's stretch of the line, left to right with no gaps: the playhead sweeps through them.
        public let slots: [Slot]
        /// From the left edge to the end of the last bar line's gap.
        public let width: CGFloat
    }

    /// Where a note or rest lies on its line: from its left edge to the next one's (across a bar line).
    public struct Slot: Sendable, Equatable {
        public let id: String
        public let left: CGFloat
        public let right: CGFloat
    }

    public enum Item: Sendable, Equatable {
        /// A note's digit centered at `center`.
        case note(id: String, start: Int, degree: Int, center: CGPoint)
        /// A rest's 0. A long rest repeats its 0 under the same id; the first one is the rest's position.
        case rest(id: String, start: Int, center: CGPoint)
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

extension ScoreLayout {
    /// Lays out the solo part. Lines take as many measures as fit, a section mark starts a new line,
    /// and every line but the last is stretched to the full width.
    public init(score: Score, width: CGFloat, metrics: ScoreMetrics = ScoreMetrics()) {
        guard let part = score.parts.first else {
            self.init(lines: [], height: 0)
            return
        }
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
            return line(measures, row: row, scale: scale, context)
        }
        self.init(lines: lines, height: metrics.lineHeight * CGFloat(lines.count))
    }
}

private func naturalWidth(_ boxes: [EventBox], _ metrics: ScoreMetrics) -> CGFloat {
    boxes.map { $0.naturalWidth(metrics) }.reduce(0, +)
}

/// Packs measures into lines: a measure starts a new line when it would not fit or when it starts a section.
private func lineGroups(widths: [CGFloat], forcedStarts: Set<Int>, available: CGFloat) -> [[Int]] {
    widths.enumerated().reduce(into: (lines: [[Int]](), used: CGFloat(0))) { packed, measure in
        let (index, width) = measure
        if packed.lines.isEmpty || forcedStarts.contains(index) || packed.used + width > available {
            packed.lines.append([index])
            packed.used = width
        } else {
            packed.lines[packed.lines.count - 1].append(index)
            packed.used += width
        }
    }.lines
}

/// Where each of `widths` starts when laid end to end from `origin`.
private func starts(of widths: [CGFloat], from origin: CGFloat) -> [CGFloat] {
    widths.dropLast().reduce(into: [origin]) { lefts, width in lefts.append((lefts.last ?? origin) + width) }
}

/// What every line of one layout shares.
private struct LineContext {
    let score: Score
    let part: Part
    let boxes: [[EventBox]]
    let metrics: ScoreMetrics
}

/// One line's stretch factor and vertical position.
private struct LineFrame {
    let scale: CGFloat
    let baseline: CGFloat
}

private func line(_ measures: [Int], row: Int, scale: CGFloat, _ context: LineContext) -> ScoreLayout.Line {
    let metrics = context.metrics
    let frame = LineFrame(scale: scale, baseline: metrics.lineHeight * (CGFloat(row) + 0.5))
    let widths = measures.map { naturalWidth(context.boxes[$0], metrics) * scale + metrics.barGap }
    let items = zip(measures, starts(of: widths, from: 0)).flatMap { index, left in
        measureItems(index, left: left, frame, context)
    }
    let slotWidths = measures.flatMap { index in
        context.boxes[index].enumerated().map { offset, box in
            box.naturalWidth(metrics) * scale + (offset == context.boxes[index].count - 1 ? metrics.barGap : 0)
        }
    }
    let slots = zip(measures.flatMap { context.boxes[$0].map(\.id) }, zip(starts(of: slotWidths, from: 0), slotWidths))
        .map { id, span in ScoreLayout.Slot(id: id, left: span.0, right: span.0 + span.1) }
    return ScoreLayout.Line(measures: measures, items: items, slots: slots, width: widths.reduce(0, +))
}

/// A measure's notes, its 减时线, and the bar line closing it.
private typealias Item = ScoreLayout.Item

private func measureItems(_ index: Int, left: CGFloat, _ frame: LineFrame, _ context: LineContext) -> [Item] {
    let (metrics, scale, baseline) = (context.metrics, frame.scale, frame.baseline)
    let boxes = context.boxes[index]
    let placed = zip(boxes, starts(of: boxes.map { $0.naturalWidth(metrics) * scale }, from: left)).map { box, left in
        placed(box, left: left, scale: scale, baseline: baseline, metrics: metrics)
    }
    let barX = left + naturalWidth(boxes, metrics) * scale + metrics.barGap / 2
    let barline = Item.barline(
        context.score.measures[index].barline, centerX: barX,
        top: baseline - metrics.lineHeight * 0.3, bottom: baseline + metrics.lineHeight * 0.3)
    return placed.flatMap(\.items)
        + underlines(placed, beams: context.part.measures[index].beams, baseline: baseline, metrics: metrics)
        + [barline]
}

extension Mark {
    fileprivate var sectionTick: Int? {
        guard case .section(let section) = self else { return nil }
        return section.tick
    }
}

extension ScoreLayout {
    /// The note or rest nearest to a tap: on the tapped line, the closest digit. Nil off the score.
    public func note(near point: CGPoint) -> String? {
        guard !lines.isEmpty, point.y >= 0, point.y < height else { return nil }
        let row = Int(point.y / (height / CGFloat(lines.count)))
        return lines[row].items.compactMap(\.head)
            .min { abs($0.center.x - point.x) < abs($1.center.x - point.x) }?.id
    }
}

extension ScoreLayout {
    /// The playhead: how far along its line a note has played. Nil when the note is not on the score.
    public func cursor(at id: String, progress: Double) -> (row: Int, x: CGFloat)? {
        lines.enumerated().lazy.compactMap { row, line in
            line.slots.first { $0.id == id }.map { slot in (row, slot.left + (slot.right - slot.left) * progress) }
        }.first
    }
}

extension ScoreLayout.Item {
    /// The digit of a note or rest: its id and where it is drawn.
    public var head: (id: String, center: CGPoint)? {
        switch self {
        case .note(let id, _, _, let center), .rest(let id, _, let center): (id, center)
        case .octaveDot, .augmentationDot, .dash, .underline, .barline: nil
        }
    }
}
