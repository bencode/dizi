import ScoreKit
import SwiftUI

/// The score page's notation: header and jianpu, drawn from the layout.
struct ScoreView: View {
    let score: Score
    private let metrics = ScoreMetrics()
    private let digitFont = Font.system(size: 24, weight: .medium, design: .rounded)

    var body: some View {
        GeometryReader { proxy in
            let layout = layoutScore(score, width: proxy.size.width - 32, metrics: metrics)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(headerText(score))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    notation(layout)
                }
                .padding(16)
            }
        }
    }

    private func notation(_ layout: ScoreLayout) -> some View {
        Canvas { context, _ in
            for item in layout.lines.flatMap(\.items) {
                draw(item, in: &context)
            }
        }
        .frame(height: layout.height)
        .accessibilityElement()
        .accessibilityIdentifier("score")
    }

    private func draw(_ item: ScoreLayout.Item, in context: inout GraphicsContext) {
        switch item {
        case .digit(_, _, let degree, let center):
            context.draw(Text("\(degree)").font(digitFont), at: center)
        case .octaveDot(_, let center):
            let radius: CGFloat = 2
            let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            context.fill(Path(ellipseIn: rect), with: .foreground)
        case .dash(_, let center, let width):
            let rect = CGRect(x: center.x - width / 2, y: center.y - 1, width: width, height: 2)
            context.fill(Path(rect), with: .foreground)
        case .barline(let style, let centerX, let top, let bottom):
            drawBarline(style, centerX: centerX, top: top, bottom: bottom, in: &context)
        }
    }

    private func drawBarline(
        _ style: Barline, centerX: CGFloat, top: CGFloat, bottom: CGFloat, in context: inout GraphicsContext
    ) {
        let strokes: [(offset: CGFloat, width: CGFloat)] =
            switch style {
            case .single: [(-0.5, 1)]
            case .double: [(-2.5, 1), (1.5, 1)]
            case .final: [(-3.5, 1), (0, 3)]
            }
        for stroke in strokes {
            let rect = CGRect(x: centerX + stroke.offset, y: top, width: stroke.width, height: bottom - top)
            context.fill(Path(rect), with: .foreground)
        }
    }
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
    let beat = [240: "♪", 480: "♩", 720: "♩.", 960: "𝅗𝅥"][tempo.beat] ?? "♩"
    switch tempo.bpm {
    case .exact(let bpm):
        return "\(beat)=\(bpm)"
    case .range(let low, let high):
        return "\(beat)=\(low)~\(high)"
    case nil:
        return tempo.text
    }
}
