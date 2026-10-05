import ScoreKit
import SwiftUI

/// The score page's notation: header and jianpu, drawn from the layout.
struct ScoreView: View {
    let score: Score
    private let metrics = ScoreMetrics(fontSize: 24)
    private var digitFont: Font { .system(size: metrics.fontSize, weight: .medium, design: .rounded) }
    private var stroke: CGFloat { metrics.fontSize / 16 }
    private var dotRadius: CGFloat { metrics.fontSize / 12 }
    private let margin: CGFloat = 16

    var body: some View {
        GeometryReader { proxy in
            let layout = layoutScore(score, width: proxy.size.width - margin * 2, metrics: metrics)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(headerText(score))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    notation(layout)
                }
                .padding(margin)
            }
        }
    }

    private func notation(_ layout: ScoreLayout) -> some View {
        let inks = layout.lines.flatMap(\.items).flatMap(ink)
        return Canvas { context, _ in
            for ink in inks {
                render(ink, in: &context)
            }
        }
        .frame(height: layout.height)
        .accessibilityElement()
        .accessibilityIdentifier("score")
    }

    /// What one layout item looks like: pure, so the canvas only paints the result.
    private func ink(_ item: ScoreLayout.Item) -> [Ink] {
        switch item {
        case .digit(_, _, let degree, let center):
            [.digit(degree, center: center)]
        case .octaveDot(_, let center), .augmentationDot(_, let center):
            [.shape(Path(ellipseIn: CGRect(origin: center, size: .zero).insetBy(dx: -dotRadius, dy: -dotRadius)))]
        case .dash(_, let center, let width):
            [.shape(Path(CGRect(x: center.x - width / 2, y: center.y - stroke, width: width, height: stroke * 2)))]
        case .underline(_, let left, let right, let lineY):
            [.shape(Path(CGRect(x: left, y: lineY - stroke / 2, width: right - left, height: stroke)))]
        case .barline(let style, let centerX, let top, let bottom):
            barlineStrokes(style).map { offset, width in
                .shape(Path(CGRect(x: centerX + offset, y: top, width: width, height: bottom - top)))
            }
        }
    }

    /// Thin and thick strokes of a bar line, as offsets from its center.
    private func barlineStrokes(_ style: Barline) -> [(offset: CGFloat, width: CGFloat)] {
        let thin = stroke * 0.7
        let thick = stroke * 2.5
        let gap = stroke * 1.5
        return switch style {
        case .single: [(-thin / 2, thin)]
        case .double: [(-gap - thin, thin), (gap, thin)]
        case .final: [(-gap - thin - thick / 2, thin), (-thick / 2, thick)]
        }
    }

    private func render(_ ink: Ink, in context: inout GraphicsContext) {
        switch ink {
        case .shape(let path):
            context.fill(path, with: .foreground)
        case .digit(let degree, let center):
            context.draw(Text("\(degree)").font(digitFont), at: center)
        }
    }
}

/// What the canvas paints.
private enum Ink {
    case shape(Path)
    case digit(Int, center: CGPoint)
}

/// `1=F  2/4  ♩=72`
private func headerText(_ score: Score) -> String {
    let key = score.header.key
    let accidental = key.accidental.map { $0 == .sharp ? "♯" : "♭" } ?? ""
    let parts: [String?] = [
        "1=\(accidental)\(key.tonic)",
        score.measures.first.flatMap { timeText($0.time) },
        score.marks.lazy.compactMap(startingTempo).first,
    ]
    return parts.compactMap { $0 }.joined(separator: "  ")
}

private func timeText(_ time: TimeSignature) -> String? {
    guard case .meter(let beats, let unit) = time else { return nil }
    return "\(beats)/\(unit)"
}

private func startingTempo(_ mark: Mark) -> String? {
    guard case .tempo(let tempo) = mark, tempo.tick == 0 else { return nil }
    // An unusual beat shows the number alone rather than a wrong note symbol.
    let beat = [240: "♪=", 480: "♩=", 720: "♩.=", 960: "𝅗𝅥="][tempo.beat] ?? ""
    return switch tempo.bpm {
    case .exact(let bpm): "\(beat)\(bpm)"
    case .range(let low, let high): "\(beat)\(low)~\(high)"
    case nil: tempo.text
    }
}
