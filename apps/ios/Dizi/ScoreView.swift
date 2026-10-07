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
        let sweep = player.sweep.map { (id: player.timeline.entries[$0.entry].id, progress: $0.progress) }
        let cursor = sweep.flatMap { layout.cursor(at: $0.id, progress: $0.progress) }
        let entries = player.timeline.entries
        let start = entries.indices.contains(player.transport.start) ? entries[player.transport.start].id : nil
        let row = cursor?.row
        return notation(layout, current: sweep?.id, cursor: cursor, start: start)
            .background(alignment: .top) { rowAnchors(layout) }
            .overlay { countdown }
            .onChange(of: row) { _, row in
                guard let row, player.isRunning else { return }
                withAnimation { scroller.scrollTo(row, anchor: .center) }
            }
    }

    private func notation(
        _ layout: ScoreLayout, current: String?, cursor: (row: Int, x: CGFloat)?, start: String?
    ) -> some View {
        let inks =
            playheadInks(layout, cursor: cursor, start: start)
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

    /// The played part of the current line filled in up to the cursor, and a small marker over the start note.
    private func playheadInks(_ layout: ScoreLayout, cursor: (row: Int, x: CGFloat)?, start: String?) -> [Ink] {
        let size = metrics.fontSize
        let rowHeight = layout.height / CGFloat(max(layout.lines.count, 1))
        let sweep = cursor.map { cursor in
            let band = CGRect(
                x: 0, y: rowHeight * (CGFloat(cursor.row) + 0.12), width: cursor.x, height: rowHeight * 0.76)
            return [
                Ink.shape(Path(roundedRect: band, cornerRadius: size * 0.2), .wash),
                Ink.shape(
                    Path(CGRect(x: cursor.x - stroke, y: band.minY, width: stroke * 2, height: band.height)), .accent),
            ]
        }
        let marker = layout.lines.flatMap(\.items).compactMap(\.head).first { $0.id == start }.map { head in
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
        return (sweep ?? []) + [marker].compactMap { $0 }
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
        case .repeatDots(let centerX, let top, let bottom):
            [top, bottom].map { dotY in
                let center = CGPoint(x: centerX, y: dotY)
                return .shape(
                    Path(ellipseIn: CGRect(origin: center, size: .zero).insetBy(dx: -dotRadius, dy: -dotRadius)), .plain
                )
            }
        case .ending(let label, let origin):
            [.label(label, point: origin, anchor: .bottomLeading)]
        case .arc(let left, let right, let endY):
            [.shape(arcPath(left: left, right: right, endY: endY), .plain)]
        case .breath(let center):
            [.label("V", point: center, anchor: .center)]
        }
    }

    /// A slur or tie as engraved: a crescent, thick in the middle and thin at its ends; it rises with its width.
    private func arcPath(left: CGFloat, right: CGFloat, endY: CGFloat) -> Path {
        let rise = min(max((right - left) * 0.12, metrics.fontSize * 0.15), metrics.fontSize * 0.4)
        let middle = (left + right) / 2
        return Path { path in
            path.move(to: CGPoint(x: left, y: endY))
            path.addQuadCurve(to: CGPoint(x: right, y: endY), control: CGPoint(x: middle, y: endY - rise * 2))
            path.addQuadCurve(
                to: CGPoint(x: left, y: endY), control: CGPoint(x: middle, y: endY - rise * 2 + stroke * 2.4))
            path.closeSubpath()
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
        case .label(let text, let point, let anchor):
            context.draw(Text(verbatim: text).font(.system(size: metrics.fontSize * 0.55)), at: point, anchor: anchor)
        }
    }
}

/// What the canvas paints.
private enum Ink {
    case shape(Path, Tone)
    case digit(Int, center: CGPoint, Tone)
    /// Small text such as an ending's number or a breath mark, placed by its `anchor` at `point`.
    case label(String, point: CGPoint, anchor: UnitPoint)
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
        score.startingTempo.flatMap(tempoText),
    ]
    return parts.compactMap { $0 }.joined(separator: "  ")
}

private func timeText(_ time: TimeSignature) -> String? {
    guard case .meter(let beats, let unit) = time else { return nil }
    return "\(beats)/\(unit)"
}

private func tempoText(_ tempo: TempoMark) -> String? {
    // An unusual beat shows the number alone rather than a wrong note symbol.
    let beat = [240: "♪=", 480: "♩=", 720: "♩.=", 960: "𝅗𝅥="][tempo.beat] ?? ""
    return switch tempo.bpm {
    case .exact(let bpm): "\(beat)\(bpm)"
    case .range(let low, let high): "\(beat)\(low)~\(high)"
    case nil: tempo.text
    }
}
