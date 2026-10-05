import CoreGraphics

/// Sizes the layout works with; the app derives them from its font.
public struct ScoreMetrics: Sendable {
    public var slotWidth: CGFloat = 30
    public var barGap: CGFloat = 16
    public var lineHeight: CGFloat = 72
    public var digitHeight: CGFloat = 24
    public var dotGap: CGFloat = 4
    public var dotSpacing: CGFloat = 6
    public var dashWidth: CGFloat = 14

    public init() {}
}

/// Where everything of a score goes, for one screen width. Positions are in the score's own coordinates.
public struct ScoreLayout: Sendable {
    public let lines: [Line]
    public let height: CGFloat

    public struct Line: Sendable {
        /// Indices into `Score.measures`.
        public let measures: [Int]
        public let items: [Item]
    }

    public enum Item: Sendable, Equatable {
        /// A note or rest digit centered at `center`; `degree` is 0 for a rest.
        case digit(id: String, start: Int, degree: Int, center: CGPoint)
        /// An octave dot of a note.
        case octaveDot(noteID: String, center: CGPoint)
        /// 增时线: one more beat of the note. Long rests repeat their 0 instead.
        case dash(noteID: String, center: CGPoint, width: CGFloat)
        case barline(Barline, centerX: CGFloat, top: CGFloat, bottom: CGFloat)
    }
}

/// Lays out the solo part: equal slots per beat-length item, lines broken where the score breaks them
/// and wherever the next measure would not fit.
public func layoutScore(_ score: Score, width: CGFloat, metrics: ScoreMetrics = ScoreMetrics()) -> ScoreLayout {
    guard let part = score.parts.first else { return ScoreLayout(lines: [], height: 0) }
    let breaks = Set(score.layoutHints?.lineBreaksAfter ?? [])
    let groups = lineGroups(
        widths: part.measures.map { measureWidth($0, metrics) },
        breaksAfter: breaks, available: width, barGap: metrics.barGap)
    let lines = groups.enumerated().map { row, measures in
        layoutLine(
            measures, part: part, score: score,
            baseline: metrics.lineHeight * (CGFloat(row) + 0.5), metrics: metrics)
    }
    return ScoreLayout(lines: lines, height: metrics.lineHeight * CGFloat(lines.count))
}

/// 增时线 after a note of this written length: none for a quarter or shorter.
func dashCount(value: Int, dots: Int) -> Int {
    guard value <= 2 else { return 0 }
    let quarters = (4 / value) * ((1 << (dots + 1)) - 1) / (1 << dots)
    return quarters - 1
}

private func slots(of event: Event) -> Int {
    if case .note(let note) = event { return 1 + dashCount(value: note.value, dots: note.dots) }
    if case .rest(let rest) = event { return 1 + dashCount(value: rest.value, dots: rest.dots) }
    return 0
}

private func measureWidth(_ measure: PartMeasure, _ metrics: ScoreMetrics) -> CGFloat {
    CGFloat(measure.events.map(slots).reduce(0, +)) * metrics.slotWidth
}

private func lineGroups(widths: [CGFloat], breaksAfter: Set<Int>, available: CGFloat, barGap: CGFloat) -> [[Int]] {
    var groups: [[Int]] = []
    var current: [Int] = []
    var used: CGFloat = 0
    for (index, width) in widths.enumerated() {
        let needed = width + barGap
        if !current.isEmpty && used + needed > available {
            groups.append(current)
            current = []
            used = 0
        }
        current.append(index)
        used += needed
        if breaksAfter.contains(index) {
            groups.append(current)
            current = []
            used = 0
        }
    }
    return current.isEmpty ? groups : groups + [current]
}

private func layoutLine(
    _ measures: [Int], part: Part, score: Score, baseline: CGFloat, metrics: ScoreMetrics
) -> ScoreLayout.Line {
    var items: [ScoreLayout.Item] = []
    var cursor: CGFloat = 0
    let top = baseline - metrics.lineHeight * 0.35
    let bottom = baseline + metrics.lineHeight * 0.35
    for index in measures {
        for event in part.measures[index].events {
            items += eventItems(event, left: cursor, baseline: baseline, metrics: metrics)
            cursor += CGFloat(slots(of: event)) * metrics.slotWidth
        }
        cursor += metrics.barGap / 2
        items.append(.barline(score.measures[index].barline, centerX: cursor, top: top, bottom: bottom))
        cursor += metrics.barGap / 2
    }
    return ScoreLayout.Line(measures: measures, items: items)
}

private func eventItems(_ event: Event, left: CGFloat, baseline: CGFloat, metrics: ScoreMetrics) -> [ScoreLayout.Item] {
    let center = CGPoint(x: left + metrics.slotWidth / 2, y: baseline)
    let shifted = { (slot: Int) in CGPoint(x: center.x + CGFloat(slot) * metrics.slotWidth, y: baseline) }
    if case .note(let note) = event {
        let dashes = (0..<dashCount(value: note.value, dots: note.dots)).map { slot in
            ScoreLayout.Item.dash(noteID: note.id, center: shifted(slot + 1), width: metrics.dashWidth)
        }
        return [.digit(id: note.id, start: note.start, degree: note.pitch.degree, center: center)]
            + octaveDots(note, center: center, metrics: metrics) + dashes
    }
    if case .rest(let rest) = event {
        // A long rest is written as repeated 0s, never with 增时线.
        return (0...dashCount(value: rest.value, dots: rest.dots)).map { slot in
            .digit(id: rest.id, start: rest.start, degree: 0, center: shifted(slot))
        }
    }
    return []
}

private func octaveDots(_ note: Note, center: CGPoint, metrics: ScoreMetrics) -> [ScoreLayout.Item] {
    let direction: CGFloat = note.pitch.octave > 0 ? -1 : 1
    let firstOffset = metrics.digitHeight / 2 + metrics.dotGap
    return (0..<abs(note.pitch.octave)).map { level in
        let dotY = center.y + direction * (firstOffset + CGFloat(level) * metrics.dotSpacing)
        return .octaveDot(noteID: note.id, center: CGPoint(x: center.x, y: dotY))
    }
}
