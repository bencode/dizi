import CoreGraphics

/// A dizi technique on a note (docs/score-format.md, 笛子技巧). Pitch arguments (颤到几, 从几滑来) are not kept yet.
public enum Technique: Decodable, Sendable, Hashable {
    /// 吐音: t, k, or 轻吐.
    case tongue(Tongue)
    case baochi
    case qiang
    /// 颤音
    case trill
    case die
    /// 打音
    case dayin
    case feizhi
    case huashe
    case fan
    case zhizhen
    case qizhen
    case fuzhen
    case rou
    case hou
    case yuanhua
    case duo
    case yanchang
    /// 波音, up (上波音) or down (下波音).
    case boyin(rising: Bool)
    /// 滑音, up (上滑音) or down (下滑音).
    case slide(rising: Bool)
    /// A technique this app does not know yet; skipped, so newer scores still open.
    case unknown

    /// The tongue's front (t), its back (k), or a light touch (轻吐).
    public enum Tongue: Sendable, Hashable {
        case front
        case back
        case light
    }

    private enum CodingKeys: String, CodingKey {
        case type, direction
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let rising = { try container.decodeIfPresent(String.self, forKey: .direction) != "down" }
        let plain: [String: Technique] = [
            "t": .tongue(.front), "k": .tongue(.back), "qingtu": .tongue(.light), "baochi": .baochi, "qiang": .qiang,
            "tr": .trill, "die": .die, "da": .dayin, "feizhi": .feizhi, "huashe": .huashe, "fan": .fan,
            "zhizhen": .zhizhen, "qizhen": .qizhen, "fuzhen": .fuzhen, "rou": .rou, "hou": .hou,
            "yuanhua": .yuanhua, "duo": .duo, "yanchang": .yanchang,
        ]
        self =
            switch type {
            case "bo": .boyin(rising: try rising())
            case "slide": .slide(rising: try rising())
            default: plain[type] ?? .unknown
            }
    }
}

/// 倚音: small notes before the main note (前倚音) or after it (后倚音, 赠音).
public struct Grace: Decodable, Sendable {
    public enum Position: String, Decodable, Sendable {
        case before
        case after
    }

    public let position: Position
    public let pitches: [Pitch]
}

/// What is written around a digit: its accidental, its technique marks, and its graces.
struct Ornaments {
    let accidental: Accidental?
    let techniques: [Technique]
    let before: [Pitch]
    let after: [Pitch]

    init(techniques: [Technique]) {
        self.init(accidental: nil, techniques: techniques, before: [], after: [])
    }

    init(_ note: Note) {
        let graces = { (position: Grace.Position) in
            note.graces.filter { $0.position == position }.flatMap(\.pitches)
        }
        self.init(
            accidental: note.pitch.accidental, techniques: note.techniques, before: graces(.before),
            after: graces(.after))
    }

    private init(accidental: Accidental?, techniques: [Technique], before: [Pitch], after: [Pitch]) {
        self.accidental = accidental
        self.techniques = techniques
        self.before = before
        self.after = after
    }

    private var slideUp: Bool { techniques.contains(.slide(rising: true)) }
    private var slideDown: Bool { techniques.contains(.slide(rising: false)) }

    /// Room before the digit: graces, then a slide up, then the accidental.
    func leadingWidth(_ metrics: ScoreMetrics) -> CGFloat {
        CGFloat(before.count) * metrics.graceAdvance + (slideUp ? metrics.slideWidth : 0)
            + (accidental == nil ? 0 : metrics.accidentalWidth)
    }

    /// Room after the digit and its 附点: a slide down, then graces.
    func trailingWidth(_ metrics: ScoreMetrics) -> CGFloat {
        (slideDown ? metrics.slideWidth : 0) + CGFloat(after.count) * metrics.graceAdvance
    }

    /// The items around a digit at `digit`, whose highest point (digit or octave dot) is `top`.
    func items(
        noteID: String, digit: CGPoint, top: CGFloat, dotsWidth: CGFloat, metrics: ScoreMetrics
    ) -> [ScoreLayout.Item] {
        let leftEdge = digit.x - metrics.digitHalfWidth
        let rightEdge = digit.x + metrics.digitHalfWidth + dotsWidth
        let accidentalX = leftEdge - metrics.accidentalWidth / 2
        let slideUpX = leftEdge - (accidental == nil ? 0 : metrics.accidentalWidth) - metrics.slideWidth / 2
        let gracesEnd =
            leftEdge - (accidental == nil ? 0 : metrics.accidentalWidth) - (slideUp ? metrics.slideWidth : 0)
        let graceY = digit.y - metrics.graceRaise
        let marks = techniques.filter { !$0.isSlide }.enumerated().map { index, technique in
            ScoreLayout.Item.technique(
                noteID: noteID, technique,
                center: CGPoint(
                    x: digit.x, y: top - metrics.dotGap - metrics.markHeight * (CGFloat(index) + 0.5)))
        }
        let slides = techniques.filter(\.isSlide).map { technique in
            let slideX = technique == .slide(rising: true) ? slideUpX : rightEdge + metrics.slideWidth / 2
            return ScoreLayout.Item.technique(noteID: noteID, technique, center: CGPoint(x: slideX, y: digit.y))
        }
        let sign =
            accidental.map {
                [
                    ScoreLayout.Item.accidental(
                        noteID: noteID, sharp: $0 == .sharp,
                        center: CGPoint(x: accidentalX, y: digit.y - metrics.fontSize * 0.25))
                ]
            } ?? []
        let leadingGraces = before.enumerated().flatMap { index, pitch in
            let centerX = gracesEnd - metrics.graceAdvance * (CGFloat(before.count - index) - 0.5)
            return graceItems(pitch, noteID: noteID, center: CGPoint(x: centerX, y: graceY), metrics: metrics)
        }
        let afterStart = rightEdge + (slideDown ? metrics.slideWidth : 0)
        let trailingGraces = after.enumerated().flatMap { index, pitch in
            let centerX = afterStart + metrics.graceAdvance * (CGFloat(index) + 0.5)
            return graceItems(pitch, noteID: noteID, center: CGPoint(x: centerX, y: graceY), metrics: metrics)
        }
        return sign + slides + leadingGraces + trailingGraces + marks
    }
}

/// A grace's small digit and its small octave dots.
private func graceItems(_ pitch: Pitch, noteID: String, center: CGPoint, metrics: ScoreMetrics) -> [ScoreLayout.Item] {
    let scale = metrics.graceScale
    let first = metrics.digitHeight * scale / 2 + metrics.dotGap * scale
    let dots = (0..<abs(pitch.octave)).map { level in
        let offset = first + CGFloat(level) * metrics.dotSpacing * scale
        return ScoreLayout.Item.graceDot(
            center: CGPoint(x: center.x, y: center.y + (pitch.octave > 0 ? -offset : offset)))
    }
    return [.grace(noteID: noteID, degree: pitch.degree, center: center)] + dots
}

extension Technique {
    var isSlide: Bool {
        if case .slide = self { true } else { false }
    }
}
