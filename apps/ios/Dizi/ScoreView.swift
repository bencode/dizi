import ScoreKit
import SwiftUI

/// The score page's notation: jianpu drawn from the layout, with the playhead on top.
struct ScoreView: View {
    let player: Player
    private let metrics = ScoreMetrics(fontSize: 24)
    private func digitFont(_ scale: CGFloat) -> Font {
        Theme.serif(metrics.fontSize * scale)
    }
    private var stroke: CGFloat { metrics.fontSize / 16 }
    private var dotRadius: CGFloat { metrics.fontSize / 12 }
    /// Narrower than the page gutter, so two measures of 16ths still fit a phone line.
    private let margin: CGFloat = 16

    var body: some View {
        GeometryReader { proxy in
            let layout = ScoreLayout(score: player.score, width: proxy.size.width - margin * 2, metrics: metrics)
            ScrollViewReader { scroller in
                ScrollView {
                    TimelineView(.animation(paused: !player.isRunning)) { _ in
                        playedNotation(layout, scroller: scroller)
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
                .font(Theme.serif(72))
                .foregroundStyle(Theme.accent.opacity(0.9))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Playing: what has been played on the wash band, up to the cursor. Stopped: the cursor at the start note.
    private func playheadInks(_ layout: ScoreLayout, cursor: (row: Int, x: CGFloat)?, start: String?) -> [Ink] {
        let size = metrics.fontSize
        let rowHeight = layout.height / CGFloat(max(layout.lines.count, 1))
        let baseline = { (row: Int) in
            layout.lines[row].items.compactMap(\.head).first?.center.y ?? rowHeight * (CGFloat(row) + 0.5)
        }
        let band = { (row: Int, width: CGFloat) in
            Ink.shape(
                Path(
                    roundedRect: CGRect(
                        x: 0, y: rowHeight * (CGFloat(row) + 0.12), width: width, height: rowHeight * 0.76),
                    cornerRadius: size * 0.2), .wash)
        }
        let sweep = cursor.map { cursor in
            (0..<cursor.row).map { band($0, layout.lines[$0].width) } + [band(cursor.row, cursor.x)]
                + [playhead(centerX: cursor.x, digitY: baseline(cursor.row))]
        }
        let marker = layout.lines.lazy.compactMap { line -> Ink? in
            let heads = line.items.compactMap(\.head)
            guard let head = heads.first(where: { $0.id == start }) else { return nil }
            // In the gap before the note: halfway from the note before, or just inside the line's start.
            let before = heads.map(\.center.x).filter { $0 < head.center.x }.max()
            let centerX = before.map { ($0 + head.center.x) / 2 } ?? max(head.center.x - size * 0.42, 1.25)
            return playhead(centerX: centerX, digitY: head.center.y)
        }.first
        return (sweep ?? []) + [marker].compactMap { $0 }
    }

    /// The accent cursor, the same while playing and stopped: 2.5 pt wide, centred on the digits.
    private func playhead(centerX: CGFloat, digitY: CGFloat) -> Ink {
        let size = metrics.fontSize
        let bar = CGRect(x: centerX - 1.25, y: digitY - size * 0.85, width: 2.5, height: size * 1.7)
        return .shape(Path(roundedRect: bar, cornerRadius: 1.25), .accent)
    }

    /// What one layout item looks like: pure, so the canvas only paints the result.
    private func ink(_ item: ScoreLayout.Item, current: String?) -> [Ink] {
        switch item {
        case .note(let id, _, let degree, let center):
            [.digit(degree, center: center, id == current ? .accent : .plain, scale: 1)]
        case .rest(let id, _, let center):
            [.digit(0, center: center, id == current ? .accent : .plain, scale: 1)]
        case .octaveDot(_, let center), .augmentationDot(_, let center):
            [dot(center, radius: dotRadius)]
        case .dash(_, let center, let width):
            [
                .shape(
                    Path(CGRect(x: center.x - width / 2, y: center.y - stroke, width: width, height: stroke * 2)),
                    .plain)
            ]
        case .underline(_, let left, let right, let lineY):
            [.shape(Path(CGRect(x: left, y: lineY - 0.75, width: right - left, height: 1.5)), .plain)]
        case .barline(let style, let centerX, let top, let bottom):
            barlineInks(style, centerX: centerX, top: top, bottom: bottom)
        case .repeatDots(let centerX, let top, let bottom):
            [top, bottom].map { dot(CGPoint(x: centerX, y: $0), radius: dotRadius) }
        case .ending(let label, let origin):
            [.mark(label, point: origin, anchor: .bottomLeading)]
        case .arc(let left, let right, let endY, let rise):
            [.shape(arcPath(left: left, right: right, endY: endY, rise: rise), .plain)]
        case .breath(let center):
            [.mark("V", point: center, anchor: .center)]
        case .accidental(_, let sharp, let center):
            [.mark(sharp ? "♯" : "♭", point: center, anchor: .center)]
        case .technique(_, let technique, let center):
            techniqueInk(technique, center: center)
        case .grace(_, let degree, let center):
            [.digit(degree, center: center, .plain, scale: metrics.graceScale)]
        case .graceDot(let center):
            [dot(center, radius: dotRadius * 0.7)]
        case .tupletNumber(let label, let center):
            [.mark(label, point: center, anchor: .center)]
        case .section(let label, let origin):
            [.label(label, point: origin, anchor: .bottomLeading, size: 13, tone: .muted)]
        }
    }

    /// A technique as jianpu marks it (docs/score-page.md): a letter or sign as text, or a small drawn shape.
    private func techniqueInk(_ technique: Technique, center: CGPoint) -> [Ink] {
        if let symbol = techniqueSigns[technique] {
            return [.mark(symbol, point: center, anchor: .center)]
        }
        return switch technique {
        case .boyin(let rising): [.shape(mordentPath(center, lower: !rising), .plain)]
        case .yanchang: [.shape(fermataPath(center), .plain), dot(center, radius: dotRadius)]
        default: []
        }
    }

    private func dot(_ center: CGPoint, radius: CGFloat) -> Ink {
        .shape(Path(ellipseIn: CGRect(origin: center, size: .zero).insetBy(dx: -radius, dy: -radius)), .plain)
    }

    /// 波音: a short double wave; the lower one has a stroke through it.
    private func mordentPath(_ center: CGPoint, lower: Bool) -> Path {
        let (width, height) = (metrics.fontSize * 0.6, metrics.fontSize * 0.12)
        let left = center.x - width / 2
        let wave = Path { path in
            path.move(to: CGPoint(x: left, y: center.y + height / 2))
            for step in 0..<4 {
                let endX = left + width * CGFloat(step + 1) / 4
                let peakY = center.y + (step.isMultiple(of: 2) ? -height : height)
                path.addQuadCurve(
                    to: CGPoint(x: endX, y: center.y + (step.isMultiple(of: 2) ? -height : height) / 2),
                    control: CGPoint(x: endX - width / 8, y: peakY))
            }
        }.strokedPath(StrokeStyle(lineWidth: stroke * 1.4, lineCap: .round))
        guard lower else { return wave }
        var marked = wave
        marked.addRect(CGRect(x: center.x - stroke / 2, y: center.y - height * 2, width: stroke, height: height * 4))
        return marked
    }

    /// 延长记号: an arc over a dot.
    private func fermataPath(_ center: CGPoint) -> Path {
        let radius = metrics.fontSize * 0.28
        return Path { path in
            path.addArc(
                center: CGPoint(x: center.x, y: center.y + radius * 0.3), radius: radius, startAngle: .degrees(180),
                endAngle: .degrees(0), clockwise: false)
        }.strokedPath(StrokeStyle(lineWidth: stroke * 1.4, lineCap: .round))
    }

    /// A slur or tie as engraved: a crescent, thick in the middle and thin at its ends.
    private func arcPath(left: CGFloat, right: CGFloat, endY: CGFloat, rise: CGFloat) -> Path {
        let middle = (left + right) / 2
        return Path { path in
            path.move(to: CGPoint(x: left, y: endY))
            path.addQuadCurve(to: CGPoint(x: right, y: endY), control: CGPoint(x: middle, y: endY - rise * 2))
            path.addQuadCurve(
                to: CGPoint(x: left, y: endY), control: CGPoint(x: middle, y: endY - rise * 2 + 3.2))
            path.closeSubpath()
        }
    }

    /// A bar line's strokes: ink at 60%, a final bar in full ink.
    private func barlineInks(_ style: Barline, centerX: CGFloat, top: CGFloat, bottom: CGFloat) -> [Ink] {
        barlineStrokes(style).map { offset, width in
            .shape(
                Path(CGRect(x: centerX + offset, y: top, width: width, height: bottom - top)),
                style == .final ? .plain : .soft)
        }
    }

    /// Thin and thick strokes of a bar line, as offsets from its center.
    private func barlineStrokes(_ style: Barline) -> [(offset: CGFloat, width: CGFloat)] {
        let thin: CGFloat = 1.2
        let thick: CGFloat = 3
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
        case .digit(let degree, let center, let tone, let scale):
            context.draw(Text(verbatim: "\(degree)").font(digitFont(scale)).foregroundStyle(tone.color), at: center)
        case .label(let text, let point, let anchor, let size, let tone):
            context.draw(
                Text(verbatim: text).font(.system(size: size)).foregroundStyle(tone.color), at: point, anchor: anchor)
        }
    }
}

/// The techniques written as a letter or sign; 波音 and 延长 are drawn as shapes instead.
private let techniqueSigns: [Technique: String] = [
    .tongue(.front): "T", .tongue(.back): "K", .tongue(.light): "▿", .baochi: "—", .qiang: ">", .trill: "tr",
    .die: "又", .dayin: "扌", .feizhi: "飞", .huashe: "✱", .fan: "○", .zhizhen: "指", .qizhen: "气", .fuzhen: "腹",
    .rou: "揉", .hou: "喉", .yuanhua: "⌒", .duo: "↓", .slide(rising: true): "↗", .slide(rising: false): "↘",
]

extension Ink {
    /// Technique marks, breath V, triplet 3, ending numbers: the contract's mark size, in ink.
    fileprivate static func mark(_ text: String, point: CGPoint, anchor: UnitPoint) -> Ink {
        .label(text, point: point, anchor: anchor, size: 12.5, tone: .plain)
    }
}

/// What the canvas paints.
private enum Ink {
    case shape(Path, Tone)
    case digit(Int, center: CGPoint, Tone, scale: CGFloat)
    /// Small text such as an ending's number or a section's name, placed by its `anchor` at `point`.
    case label(String, point: CGPoint, anchor: UnitPoint, size: CGFloat, tone: Tone)
}

/// Plain notation, the accent for the playhead, a light wash behind the current note.
private enum Tone {
    case plain
    /// Bar lines: ink, lighter than the notes.
    case soft
    case muted
    case accent
    case wash

    var color: Color {
        switch self {
        case .plain: Theme.ink
        case .soft: Theme.ink.opacity(0.6)
        case .muted: Theme.muted
        case .accent: Theme.accent
        case .wash: Theme.wash
        }
    }
}

/// The pinned line above the score: `1=F  2/4`, the practice tempo `− ♩=72 +`, then 全按作5 and the composer.
struct ScoreHeader: View {
    @Bindable var player: Player

    var body: some View {
        let score = player.score
        let fingering = score.header.fingering.map { "全按作\($0.degree)" }
        let right = [fingering, score.meta.composer].compactMap { $0 }.joined(separator: " · ")
        HStack(spacing: 0) {
            Text(verbatim: headerText(score))
                .padding(.trailing, Theme.Space.small)
            tempo
                .disabled(player.isRunning)
                .opacity(player.isRunning ? 0.4 : 1)
            Spacer(minLength: Theme.Space.small)
            Text(verbatim: right).lineLimit(1)
        }
        .font(.footnote)
        .foregroundStyle(Theme.muted)
        .frame(height: 44)
        .padding(.horizontal, Theme.Space.gutter)
        .overlay(alignment: .bottom) { Theme.rule.frame(height: 1).padding(.horizontal, Theme.Space.gutter) }
    }

    private var tempo: some View {
        HStack(spacing: 0) {
            Button {
                player.bpm = max(Player.tempoRange.lowerBound, player.bpm - 1)
            } label: {
                Label("减慢", systemImage: "minus").frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .disabled(player.bpm <= Player.tempoRange.lowerBound)
            Text(verbatim: "\(beatSymbol(player.score.startingTempo?.beat))\(player.bpm)")
                .font(Theme.serif(15))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .fixedSize()
            Button {
                player.bpm = min(Player.tempoRange.upperBound, player.bpm + 1)
            } label: {
                Label("加快", systemImage: "plus").frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .disabled(player.bpm >= Player.tempoRange.upperBound)
        }
        .labelStyle(.iconOnly)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(Theme.ink)
        .buttonRepeatBehavior(.enabled)
    }
}

/// `1=F  2/4`
private func headerText(_ score: Score) -> String {
    let key = score.header.key
    let accidental = key.accidental.map { $0 == .sharp ? "♯" : "♭" } ?? ""
    let parts: [String?] = [
        "1=\(accidental)\(key.tonic)",
        score.measures.first.flatMap { timeText($0.time) },
    ]
    return parts.compactMap { $0 }.joined(separator: "  ")
}

private func timeText(_ time: TimeSignature) -> String? {
    guard case .meter(let beats, let unit) = time else { return nil }
    return "\(beats)/\(unit)"
}

/// `♩=` for a quarter-note beat; an unusual beat shows the number alone rather than a wrong note symbol.
private func beatSymbol(_ beat: Int?) -> String {
    [240: "♪=", 480: "♩=", 720: "♩.=", 960: "𝅗𝅥="][beat ?? 480] ?? ""
}
