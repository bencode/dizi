import ScoreKit
import SwiftUI

/// A card in the list: a tile with the title's first character, the title and its line of facts, the level.
struct PieceCard: View {
    let row: ShelfRow

    var body: some View {
        HStack(spacing: Theme.Space.medium) {
            Text(verbatim: String(title.prefix(1)))
                .font(.title3.weight(.medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 38, height: 38)
                .background(Theme.tile, in: RoundedRectangle(cornerRadius: 10))
                // The glyph fills a fixed tile.
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: title).font(.body).foregroundStyle(Theme.ink).lineLimit(1)
                meta.font(.footnote).foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
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

    private var level: Stage {
        switch row {
        case .piece(let piece): piece.level
        case .series(let series): series.level
        }
    }

    /// ` · 进阶` in accent on a 进阶 card; 入门 cards carry no mark.
    @ViewBuilder private var advancedTag: some View {
        if level == .advanced {
            Text(verbatim: " · ")
            Text(levelTitle(.advanced)).foregroundStyle(Theme.accent)
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
                advancedTag
            }
        case .series(let series):
            HStack(spacing: 0) {
                if let lesson = series.firstLesson {
                    Text("\(series.pieces.count) 首 · 第\(lesson)课起")
                } else {
                    Text("\(series.pieces.count) 首")
                }
                advancedTag
            }
        }
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
