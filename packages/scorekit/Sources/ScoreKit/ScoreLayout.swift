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
    /// One technique mark's height; marks stack upward.
    var markHeight: CGFloat { fontSize * 0.6 }
    public var graceScale: CGFloat { 0.55 }
    var graceAdvance: CGFloat { fontSize * 0.4 }
    var graceRaise: CGFloat { fontSize * 0.3 }
    var accidentalWidth: CGFloat { fontSize * 0.35 }
    var slideWidth: CGFloat { fontSize * 0.5 }
}

/// Where everything of a score goes, for one screen width. Positions are in the score's own coordinates.
public struct ScoreLayout: Sendable {
    public let lines: [Line]
    public let height: CGFloat

    public struct Line: Sendable {
        /// Indices into `Score.measures`.
        public let measures: [Int]
        public let items: [Item]
        /// Each note's digit at the tick it starts, in order: the points the playhead passes through.
        public let anchors: [Anchor]
        /// The tick where the line's last measure ends; the playhead reaches the line's end then.
        public let endTick: Int
        /// From the left edge to the end of the last bar line's gap.
        public let width: CGFloat
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
        /// The two dots of a repeat sign, beside a bar line.
        case repeatDots(centerX: CGFloat, top: CGFloat, bottom: CGFloat)
        /// An ending's number (`1.`, `1.2.`) over its first measure, at its text's leading baseline point.
        case ending(label: String, origin: CGPoint)
        /// A slur or tie above the notes, from `left` to `right` with its ends at `endY`, rising `rise` in its
        /// middle; the piece of one that continues from the line before or onto the next line runs to that edge.
        case arc(left: CGFloat, right: CGFloat, endY: CGFloat, rise: CGFloat)
        /// 换气 V, centered at `center`.
        case breath(center: CGPoint)
        /// A small ♯ or ♭ before a digit.
        case accidental(noteID: String, sharp: Bool, center: CGPoint)
        /// One technique mark: above its note, or beside it for a slide.
        case technique(noteID: String, Technique, center: CGPoint)
        /// A grace note's small digit.
        case grace(noteID: String, degree: Int, center: CGPoint)
        /// A grace note's octave dot.
        case graceDot(center: CGPoint)
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
        let laidOut = { (headroom: CGFloat) in
            let context = LineContext(score: score, part: part, boxes: boxes, metrics: metrics, headroom: headroom)
            let lines = groups.enumerated().map { row, measures in
                let natural = measures.map { naturalWidth(boxes[$0], metrics) }.reduce(0, +)
                let gaps = CGFloat(measures.count) * metrics.barGap
                let isLast = row == groups.count - 1
                let scale = isLast || natural == 0 ? 1 : max(1, (width - gaps) / natural)
                return line(measures, row: row, scale: scale, context)
            }
            return phrased(lines, score: score, metrics: metrics)
        }
        // Marks and slurs over high notes can reach above a line's top; then every line grows by that much.
        let plain = laidOut(0)
        let headroom = overshoot(plain, metrics: metrics)
        let lines = headroom > 0 ? laidOut(headroom) : plain
        self.init(lines: lines, height: (metrics.lineHeight + headroom) * CGFloat(lines.count))
    }
}

/// How far the highest content of any line reaches above that line's top, with a little air; 0 when all fits.
private func overshoot(_ lines: [ScoreLayout.Line], metrics: ScoreMetrics) -> CGFloat {
    let reach = lines.enumerated().map { row, line in
        metrics.lineHeight * CGFloat(row) - (line.items.map { $0.highestPoint(metrics) }.min() ?? 0)
    }
    let most = reach.max() ?? 0
    return most > 0 ? most + metrics.dotGap : 0
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
    /// Room added above every line, so tall marks fit.
    let headroom: CGFloat
}

/// One line's stretch factor and vertical position.
private struct LineFrame {
    let scale: CGFloat
    let baseline: CGFloat
}

private func line(_ measures: [Int], row: Int, scale: CGFloat, _ context: LineContext) -> ScoreLayout.Line {
    let metrics = context.metrics
    let rowHeight = metrics.lineHeight + context.headroom
    let frame = LineFrame(scale: scale, baseline: rowHeight * CGFloat(row) + context.headroom + metrics.lineHeight / 2)
    let widths = measures.map { naturalWidth(context.boxes[$0], metrics) * scale + metrics.barGap }
    let items = zip(measures, starts(of: widths, from: 0)).flatMap { index, left in
        measureItems(index, left: left, frame, context)
    }
    // A long rest repeats its digit under one id; the first is where it starts.
    let anchors = items.compactMap(\.anchor).reduce(into: [Anchor]()) { anchors, anchor in
        if anchors.last?.id != anchor.id {
            anchors.append(anchor)
        }
    }
    let lastMeasure = measures.last.map { context.score.measures[$0] }
    return ScoreLayout.Line(
        measures: measures, items: items, anchors: anchors,
        endTick: lastMeasure.map { $0.start + $0.duration } ?? 0, width: widths.reduce(0, +))
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
        + [barline] + repeats(index, span: left...barX, frame, context)
}

/// Repeat dots inside the measure's bar lines, and the ending's number where an ending begins.
private func repeats(_ index: Int, span: ClosedRange<CGFloat>, _ frame: LineFrame, _ context: LineContext) -> [Item] {
    let (metrics, left, barX, baseline) = (context.metrics, span.lowerBound, span.upperBound, frame.baseline)
    let measure = context.score.measures[index]
    let dots = { (centerX: CGFloat) in
        Item.repeatDots(centerX: centerX, top: baseline - metrics.dotSpacing, bottom: baseline + metrics.dotSpacing)
    }
    let previousVolta = index > 0 ? context.score.measures[index - 1].volta : nil
    let ending = measure.volta.flatMap { volta -> Item? in
        guard volta != previousVolta else { return nil }
        let label = volta.map { "\($0)." }.joined()
        return .ending(label: label, origin: CGPoint(x: left, y: baseline - metrics.lineHeight * 0.38))
    }
    return (measure.repeatStart ? [dots(left + metrics.dotGap)] : [])
        + (measure.repeatEnd ? [dots(barX - metrics.barGap * 0.4)] : [])
        + (ending.map { [$0] } ?? [])
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
    /// The playhead while a note sounds: on the note's digit when it starts, on the next one's when that
    /// starts, moving smoothly in between. Nil when the note is not on the score.
    public func cursor(at id: String, progress: Double) -> (row: Int, x: CGFloat)? {
        lines.enumerated().lazy.compactMap { row, line -> (row: Int, x: CGFloat)? in
            guard let index = line.anchors.firstIndex(where: { $0.id == id }) else { return nil }
            let points =
                line.anchors.map { (tick: Double($0.tick), position: $0.position) }
                + [(tick: Double(line.endTick), position: line.width)]
            let tick = points[index].tick + progress * (points[index + 1].tick - points[index].tick)
            return (row, smoothPosition(at: tick, through: points))
        }.first
    }
}

extension ScoreLayout.Item {
    /// The top of what the item draws.
    fileprivate func highestPoint(_ metrics: ScoreMetrics) -> CGFloat {
        switch self {
        case .note(_, _, _, let center), .rest(_, _, let center): center.y - metrics.digitHeight / 2
        case .octaveDot(_, let center), .augmentationDot(_, let center), .graceDot(let center):
            center.y - metrics.dotSpacing / 2
        case .dash(_, let center, _): center.y
        case .underline(_, _, _, let lineY): lineY
        case .barline(_, _, let top, _): top
        case .repeatDots(_, let top, _): top - metrics.dotSpacing / 2
        case .ending(_, let origin): origin.y - metrics.fontSize * 0.55
        case .arc(_, _, let endY, let rise): endY - rise
        case .breath(let center), .accidental(_, _, let center): center.y - metrics.fontSize * 0.3
        case .technique(_, _, let center): center.y - metrics.markHeight / 2
        case .grace(_, _, let center): center.y - metrics.digitHeight * metrics.graceScale / 2
        }
    }

    /// A note's or rest's digit as a point the playhead passes.
    fileprivate var anchor: Anchor? {
        switch self {
        case .note(let id, let start, _, let center), .rest(let id, let start, let center):
            Anchor(id: id, tick: start, position: center.x)
        case .octaveDot, .augmentationDot, .dash, .underline, .barline, .repeatDots, .ending, .arc, .breath,
            .accidental, .technique, .grace, .graceDot:
            nil
        }
    }

    /// The digit of a note or rest: its id and where it is drawn.
    public var head: (id: String, center: CGPoint)? {
        switch self {
        case .note(let id, _, _, let center), .rest(let id, _, let center): (id, center)
        case .octaveDot, .augmentationDot, .dash, .underline, .barline, .repeatDots, .ending, .arc, .breath,
            .accidental, .technique, .grace, .graceDot:
            nil
        }
    }
}
