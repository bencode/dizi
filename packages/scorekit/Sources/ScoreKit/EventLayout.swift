import CoreGraphics

/// One note or rest as jianpu writes it: a digit with its 减时线, 附点, and octave dots, then 增时线
/// (or, for a long rest, more 0s).
struct EventBox {
    enum Head {
        case note(degree: Int, octave: Int)
        case rest
    }

    let id: String
    let start: Int
    let head: Head
    let underlines: Int
    let augmentationDots: Int
    let extensions: Int
    let ornaments: Ornaments

    /// The digit and its 附点.
    func headWidth(_ metrics: ScoreMetrics) -> CGFloat {
        max(metrics.quarterWidth * spacingFactor, metrics.minimumHeadWidth)
            + CGFloat(augmentationDots) * metrics.augmentationDotWidth
    }

    /// The head with the ornaments written before and after it, then the 增时线.
    func naturalWidth(_ metrics: ScoreMetrics) -> CGFloat {
        ornaments.leadingWidth(metrics) + headWidth(metrics) + ornaments.trailingWidth(metrics)
            + CGFloat(extensions) * metrics.quarterWidth
    }

    /// Shorter notes sit closer together.
    private var spacingFactor: CGFloat {
        [0: 1, 1: 0.75, 2: 0.6][underlines] ?? 0.5
    }
}

func eventBox(_ event: Event) -> EventBox? {
    switch event {
    case .note(let note):
        EventBox(
            id: note.id, start: note.start, head: .note(degree: note.pitch.degree, octave: note.pitch.octave),
            shape: Shape(value: note.value, dots: note.dots), ornaments: Ornaments(note))
    case .rest(let rest):
        EventBox(
            id: rest.id, start: rest.start, head: .rest, shape: Shape(value: rest.value, dots: rest.dots),
            ornaments: Ornaments(techniques: rest.techniques))
    case .unknown:
        nil
    }
}

extension EventBox {
    fileprivate init(id: String, start: Int, head: Head, shape: Shape, ornaments: Ornaments) {
        self.init(
            id: id, start: start, head: head, underlines: shape.underlines,
            augmentationDots: shape.augmentationDots, extensions: shape.dashes, ornaments: ornaments)
    }
}

/// How jianpu writes a written length: 减时线 below, 附点 beside, or 增时线 after.
private struct Shape {
    let underlines: Int
    let augmentationDots: Int
    let dashes: Int

    init(value: NoteValue, dots: Dots) {
        dashes = dashCount(value: value, dots: dots)
        underlines = value.rawValue > 4 ? value.rawValue.trailingZeroBitCount - 2 : 0
        augmentationDots = dashes == 0 ? dots.rawValue : 0
    }
}

/// 增时线 after a note of this written length: none for a quarter or shorter.
func dashCount(value: NoteValue, dots: Dots) -> Int {
    guard value.rawValue <= 2 else { return 0 }
    let quarters = (4 / value.rawValue) * ((1 << (dots.rawValue + 1)) - 1) / (1 << dots.rawValue)
    return quarters - 1
}

/// A box placed on a line: its items, and the horizontal span its 减时线 must cover.
struct PlacedBox {
    let box: EventBox
    let items: [ScoreLayout.Item]
    let span: ClosedRange<CGFloat>
}

func placed(_ box: EventBox, left: CGFloat, scale: CGFloat, baseline: CGFloat, metrics: ScoreMetrics) -> PlacedBox {
    let dotsWidth = CGFloat(box.augmentationDots) * metrics.augmentationDotWidth
    let leading = box.ornaments.leadingWidth(metrics)
    let digitX = left + (leading + (box.headWidth(metrics) - dotsWidth) / 2) * scale
    let digit = CGPoint(x: digitX, y: baseline)
    let augmentationDots = (0..<box.augmentationDots).map { index in
        let dotX = digitX + metrics.digitHalfWidth + metrics.augmentationDotWidth * (CGFloat(index) + 0.5)
        return ScoreLayout.Item.augmentationDot(noteID: box.id, center: CGPoint(x: dotX, y: baseline))
    }
    let extensions = (0..<box.extensions).map { index in
        let before = leading + box.headWidth(metrics) + box.ornaments.trailingWidth(metrics)
        let center = CGPoint(x: left + (before + metrics.quarterWidth * (CGFloat(index) + 0.5)) * scale, y: baseline)
        let item: ScoreLayout.Item =
            switch box.head {
            case .note: .dash(noteID: box.id, center: center, width: metrics.dashWidth)
            case .rest: .rest(id: box.id, start: box.start, center: center)
            }
        return item
    }
    let head: ScoreLayout.Item =
        switch box.head {
        case .note(let degree, _): .note(id: box.id, start: box.start, degree: degree, center: digit)
        case .rest: .rest(id: box.id, start: box.start, center: digit)
        }
    let dots = octaveDots(box, digit: digit, metrics: metrics)
    let ornaments = box.ornaments.items(
        noteID: box.id, digit: digit, top: topOfHead(digit, dots, metrics), dotsWidth: dotsWidth, metrics: metrics)
    let items = [head] + dots + augmentationDots + extensions + ornaments
    let right = digitX + metrics.digitHalfWidth + dotsWidth
    return PlacedBox(box: box, items: items, span: (digitX - metrics.digitHalfWidth)...right)
}

private func octaveDots(_ box: EventBox, digit: CGPoint, metrics: ScoreMetrics) -> [ScoreLayout.Item] {
    guard case .note(_, let octave) = box.head else { return [] }
    let above = octave > 0
    let underlineDepth =
        box.underlines > 0 ? metrics.underlineGap + CGFloat(box.underlines) * metrics.underlineSpacing : 0
    let firstOffset = metrics.digitHeight / 2 + metrics.dotGap + (above ? 0 : underlineDepth)
    return (0..<abs(octave)).map { level in
        let offset = firstOffset + CGFloat(level) * metrics.dotSpacing
        let center = CGPoint(x: digit.x, y: digit.y + (above ? -offset : offset))
        return .octaveDot(noteID: box.id, center: center)
    }
}

/// The top of a digit and the octave dots above it: technique marks stack from here.
private func topOfHead(_ digit: CGPoint, _ dots: [ScoreLayout.Item], _ metrics: ScoreMetrics) -> CGFloat {
    let dotTops = dots.compactMap { item -> CGFloat? in
        guard case .octaveDot(_, let center) = item, center.y < digit.y else { return nil }
        return center.y - metrics.dotSpacing / 2
    }
    return dotTops.min() ?? digit.y - metrics.digitHeight / 2
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
