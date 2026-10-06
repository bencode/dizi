import ScoreKit
import SwiftUI

/// The score page's notation: header and jianpu drawn from the layout, with the playhead on top.
struct ScoreView: View {
    let player: Player
    private let metrics = ScoreMetrics(fontSize: 24)
    private var digitFont: Font { .system(size: metrics.fontSize, weight: .medium, design: .rounded) }
    private var stroke: CGFloat { metrics.fontSize / 16 }
    private var dotRadius: CGFloat { metrics.fontSize / 12 }
    private let margin: CGFloat = 16

    var body: some View {
        GeometryReader { proxy in
            let layout = ScoreLayout(score: player.score, width: proxy.size.width - margin * 2, metrics: metrics)
            ScrollViewReader { scroller in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(headerText(player.score))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        TimelineView(.animation(paused: !player.isRunning)) { _ in
                            playedNotation(layout, scroller: scroller)
                        }
                    }
                    .padding(margin)
                }
            }
        }
    }

    /// The notation as it stands this frame: the current note lit, the start marked, the page following.
    private func playedNotation(_ layout: ScoreLayout, scroller: ScrollViewProxy) -> some View {
        let current = player.highlighted.map { player.timeline.entries[$0].id }
        let start = player.timeline.entries[player.transport.start].id
        let row = current.flatMap { id in layout.lines.firstIndex { $0.items.contains { $0.head?.id == id } } }
        return notation(layout, current: current, start: start)
            .background(alignment: .top) { rowAnchors(layout) }
            .overlay { countdown }
            .onChange(of: row) { _, row in
                guard let row, player.isRunning else { return }
                withAnimation { scroller.scrollTo(row, anchor: .center) }
            }
    }

    private func notation(_ layout: ScoreLayout, current: String?, start: String) -> some View {
        let inks =
            playheadInks(layout, current: current, start: start)
            + layout.lines.flatMap(\.items).flatMap { ink($0, current: current) }
        return Canvas { context, _ in
            for ink in inks {
                render(ink, in: &context)
            }
        }
        .frame(height: layout.height)
        .contentShape(Rectangle())
        .onTapGesture { location in
            if let id = layout.note(near: location) {
                player.select(noteID: id)
            }
        }
        .accessibilityElement()
        .accessibilityIdentifier("score")
    }

    /// One invisible view per line, so the page can scroll to a line.
    private func rowAnchors(_ layout: ScoreLayout) -> some View {
        VStack(spacing: 0) {
            ForEach(layout.lines.indices, id: \.self) { row in
                Color.clear.frame(height: layout.height / CGFloat(layout.lines.count)).id(row)
            }
        }
    }

    @ViewBuilder private var countdown: some View {
        if case .countIn(let beatsLeft) = player.position {
            Text(verbatim: "\(beatsLeft)")
                .font(.system(size: 96, weight: .bold, design: .rounded))
                .foregroundStyle(.tint)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    /// A soft background under the current note and a small marker over the start note.
    private func playheadInks(_ layout: ScoreLayout, current: String?, start: String) -> [Ink] {
        let heads = layout.lines.flatMap(\.items).compactMap(\.head)
        let size = metrics.fontSize
        let wash = heads.first { $0.id == current }.map { head in
            Ink.shape(
                Path(
                    roundedRect: CGRect(
                        x: head.center.x - size * 0.5, y: head.center.y - size * 0.75,
                        width: size, height: size * 1.5), cornerRadius: size * 0.25),
                .wash)
        }
        let marker = heads.first { $0.id == start }.map { head in
            let tip = CGPoint(x: head.center.x, y: head.center.y - size * 1.05)
            return Ink.shape(
                Path { path in
                    path.addLines([
                        tip, CGPoint(x: tip.x - size / 5, y: tip.y - size / 4),
                        CGPoint(x: tip.x + size / 5, y: tip.y - size / 4),
                    ])
                    path.closeSubpath()
                }, .accent)
        }
        return [wash, marker].compactMap { $0 }
    }

    /// What one layout item looks like: pure, so the canvas only paints the result.
    private func ink(_ item: ScoreLayout.Item, current: String?) -> [Ink] {
        switch item {
        case .note(let id, _, let degree, let center):
            [.digit(degree, center: center, id == current ? .accent : .plain)]
        case .rest(let id, _, let center):
            [.digit(0, center: center, id == current ? .accent : .plain)]
        case .octaveDot(_, let center), .augmentationDot(_, let center):
            [
                .shape(
                    Path(ellipseIn: CGRect(origin: center, size: .zero).insetBy(dx: -dotRadius, dy: -dotRadius)), .plain
                )
            ]
        case .dash(_, let center, let width):
            [
                .shape(
                    Path(CGRect(x: center.x - width / 2, y: center.y - stroke, width: width, height: stroke * 2)),
                    .plain)
            ]
        case .underline(_, let left, let right, let lineY):
            [.shape(Path(CGRect(x: left, y: lineY - stroke / 2, width: right - left, height: stroke)), .plain)]
        case .barline(let style, let centerX, let top, let bottom):
            barlineStrokes(style).map { offset, width in
                .shape(Path(CGRect(x: centerX + offset, y: top, width: width, height: bottom - top)), .plain)
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
        case .shape(let path, let tone):
            context.fill(path, with: .color(tone.color))
        case .digit(let degree, let center, let tone):
            context.draw(Text(verbatim: "\(degree)").font(digitFont).foregroundStyle(tone.color), at: center)
        }
    }
}

/// What the canvas paints.
private enum Ink {
    case shape(Path, Tone)
    case digit(Int, center: CGPoint, Tone)
}

/// Plain notation, the accent for the playhead, a light wash behind the current note.
private enum Tone {
    case plain
    case accent
    case wash

    var color: Color {
        switch self {
        case .plain: .primary
        case .accent: .accentColor
        case .wash: .accentColor.opacity(0.18)
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
    // An unusual beat shows the number alone rather than a wrong note symbol.
    let beat = [240: "♪=", 480: "♩=", 720: "♩.=", 960: "𝅗𝅥="][tempo.beat] ?? ""
    return switch tempo.bpm {
    case .exact(let bpm): "\(beat)\(bpm)"
    case .range(let low, let high): "\(beat)\(low)~\(high)"
    case nil: tempo.text
    }
}
