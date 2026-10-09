import ScoreKit
import SwiftUI

/// A card in the list: a tile with the title's first character, the title and its line of facts, the level.
struct PieceCard: View {
    let row: ShelfRow
    @Environment(\.colorScheme) private var colorScheme
    @Environment(SongFont.self) private var song

    var body: some View {
        HStack(spacing: Theme.Space.medium) {
            Text(verbatim: String(title.prefix(1)))
                .font(song.font(19))
                .foregroundStyle(Theme.accent)
                .frame(width: 38, height: 38)
                .background(Theme.tile, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: title).font(song.font(17)).foregroundStyle(Theme.ink).lineLimit(1)
                meta.font(.footnote).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
            levelDots
        }
        .padding(.vertical, Theme.Space.medium)
        .padding(.horizontal, 14)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.rule, lineWidth: 1) }
        .accessibilityElement(children: .combine)
        .accessibilityValue(Text(levelTitle(level)))
    }

    private var title: String {
        switch row {
        case .piece(let piece): piece.title
        case .series(let series): series.name
        }
    }

    private var level: Int {
        switch row {
        case .piece(let piece): piece.level
        case .series(let series): series.level
        }
    }

    @ViewBuilder private var meta: some View {
        switch row {
        case .piece(let piece):
            HStack(spacing: 0) {
                Text(verbatim: "\(piece.key) · \(piece.time)")
                if let lesson = piece.lesson {
                    Text(verbatim: " · ")
                    Text("第\(lesson)课")
                }
            }
        case .series(let series):
            if let lesson = series.firstLesson {
                Text("\(series.pieces.count) 首 · 第\(lesson)课起")
            } else {
                Text("\(series.pieces.count) 首")
            }
        }
    }

    /// Four dots, as many lit as the level: accent, gold in the dark.
    private var levelDots: some View {
        HStack(spacing: 3) {
            ForEach(1...4, id: \.self) { dot in
                Circle()
                    .fill(dot <= level ? (colorScheme == .dark ? Theme.gold : Theme.accent) : Theme.dotOff)
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The pieces of one series, as cards.
struct SeriesView: View {
    let series: PieceSeries

    var body: some View {
        List(series.pieces) { piece in
            NavigationLink(value: piece) { PieceCard(row: .piece(piece)) }
                .cardLink()
                .cardRow()
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.ground)
        .navigationTitle(Text(verbatim: series.name))
        .navigationBarTitleDisplayMode(.inline)
    }
}
