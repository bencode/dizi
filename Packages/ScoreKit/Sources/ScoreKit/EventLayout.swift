import CoreGraphics

/// One note or rest as jianpu writes it: a digit with its 减时线, 附点, and octave dots, then 增时线
/// (or, for a long rest, more 0s).
struct EventBox {
    let id: String
    let start: Int
    /// 0 for a rest.
    let degree: Int
    let octave: Int
    let underlines: Int
    let augmentationDots: Int
    let extensions: Int

    /// The digit and its 附点.
    func headWidth(_ metrics: ScoreMetrics) -> CGFloat {
        max(metrics.quarterWidth * spacingFactor, metrics.minimumHeadWidth)
            + CGFloat(augmentationDots) * metrics.augmentationDotWidth
    }

    func naturalWidth(_ metrics: ScoreMetrics) -> CGFloat {
        headWidth(metrics) + CGFloat(extensions) * metrics.quarterWidth
    }

    /// Shorter notes sit closer together.
    private var spacingFactor: CGFloat {
        [0: 1, 1: 0.75, 2: 0.6][underlines] ?? 0.5
    }
}

func eventBox(_ event: Event) -> EventBox? {
    if case .note(let note) = event {
        let shape = Shape(value: note.value, dots: note.dots)
        return EventBox(
            id: note.id, start: note.start, degree: note.pitch.degree, octave: note.pitch.octave,
            underlines: shape.underlines, augmentationDots: shape.augmentationDots, extensions: shape.dashes)
    }
    if case .rest(let rest) = event {
        let shape = Shape(value: rest.value, dots: rest.dots)
        return EventBox(
            id: rest.id, start: rest.start, degree: 0, octave: 0,
            underlines: shape.underlines, augmentationDots: shape.augmentationDots, extensions: shape.dashes)
    }
    return nil
}

/// How jianpu writes a written length: 减时线 below, 附点 beside, or 增时线 after.
private struct Shape {
    let underlines: Int
    let augmentationDots: Int
    let dashes: Int

    init(value: Int, dots: Int) {
        dashes = dashCount(value: value, dots: dots)
        underlines = value > 4 ? value.trailingZeroBitCount - 2 : 0
        augmentationDots = dashes == 0 ? dots : 0
    }
}

/// 增时线 after a note of this written length: none for a quarter or shorter.
func dashCount(value: Int, dots: Int) -> Int {
    guard value <= 2 else { return 0 }
    let quarters = (4 / value) * ((1 << (dots + 1)) - 1) / (1 << dots)
    return quarters - 1
}

/// A box placed on a line: its items, and the horizontal span its 减时线 must cover.
struct PlacedBox {
    let box: EventBox
    let items: [ScoreLayout.Item]
    let span: ClosedRange<CGFloat>
}

func placeBox(_ box: EventBox, left: CGFloat, scale: CGFloat, baseline: CGFloat, metrics: ScoreMetrics) -> PlacedBox {
    let dotsWidth = CGFloat(box.augmentationDots) * metrics.augmentationDotWidth
    let digitX = left + (box.headWidth(metrics) - dotsWidth) * scale / 2
    let digit = CGPoint(x: digitX, y: baseline)
    let augmentationDots = (0..<box.augmentationDots).map { index in
        let dotX = digitX + metrics.digitHalfWidth + metrics.augmentationDotWidth * (CGFloat(index) + 0.5)
        return ScoreLayout.Item.augmentationDot(noteID: box.id, center: CGPoint(x: dotX, y: baseline))
    }
    let extensions = (0..<box.extensions).map { index in
        let center = CGPoint(
            x: left + (box.headWidth(metrics) + metrics.quarterWidth * (CGFloat(index) + 0.5)) * scale, y: baseline)
        return box.degree == 0
            ? ScoreLayout.Item.digit(id: box.id, start: box.start, degree: 0, center: center)
            : .dash(noteID: box.id, center: center, width: metrics.dashWidth)
    }
    let items =
        [.digit(id: box.id, start: box.start, degree: box.degree, center: digit)]
        + octaveDots(box, digit: digit, metrics: metrics) + augmentationDots + extensions
    let right = digitX + metrics.digitHalfWidth + dotsWidth
    return PlacedBox(box: box, items: items, span: (digitX - metrics.digitHalfWidth)...right)
}

private func octaveDots(_ box: EventBox, digit: CGPoint, metrics: ScoreMetrics) -> [ScoreLayout.Item] {
    let above = box.octave > 0
    let underlineDepth =
        box.underlines > 0 ? metrics.underlineGap + CGFloat(box.underlines) * metrics.underlineSpacing : 0
    let firstOffset = metrics.digitHeight / 2 + metrics.dotGap + (above ? 0 : underlineDepth)
    return (0..<abs(box.octave)).map { level in
        let offset = firstOffset + CGFloat(level) * metrics.dotSpacing
        let center = CGPoint(x: digit.x, y: digit.y + (above ? -offset : offset))
        return .octaveDot(noteID: box.id, center: center)
    }
}

/// 减时线 of one measure: a beam of a level joins its notes into one line; other short notes get their own.
func underlines(_ placed: [PlacedBox], beams: [Beam], baseline: CGFloat, metrics: ScoreMetrics) -> [ScoreLayout.Item] {
    // A malformed score may repeat an id; keep the first rather than trap.
    let position = Dictionary(placed.enumerated().map { ($1.box.id, $0) }, uniquingKeysWith: { first, _ in first })
    let deepest = placed.map(\.box.underlines).max() ?? 0
    return (0..<deepest).flatMap { depth in
        let level = depth + 1
        let lineY =
            baseline + metrics.digitHeight / 2 + metrics.underlineGap + CGFloat(depth) * metrics.underlineSpacing
        let groups = beams.filter { $0.level == level }.compactMap { beam -> ClosedRange<Int>? in
            guard let first = position[beam.first], let last = position[beam.last], first <= last else { return nil }
            return first...last
        }
        let singles = placed.indices.filter { index in
            placed[index].box.underlines >= level && !groups.contains { $0.contains(index) }
        }
        return (groups + singles.map { $0...$0 }).map { group in
            ScoreLayout.Item.underline(
                level: level, left: placed[group.lowerBound].span.lowerBound,
                right: placed[group.upperBound].span.upperBound, lineY: lineY)
        }
    }
}
