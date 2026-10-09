import ScoreKit
import SwiftUI

struct PieceListView: View {
    @Environment(LibraryStore.self) private var library
    @Environment(SongFont.self) private var song
    @State private var query = ""
    @State private var level: Int?

    var body: some View {
        content
            .navigationTitle("曲目")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: LibraryPiece.self) { piece in
                PieceDetailView(piece: piece)
            }
            .navigationDestination(for: PieceSeries.self) { series in
                SeriesView(series: series)
            }
    }

    @ViewBuilder private var content: some View {
        switch library.catalog {
        case .success(let catalog):
            let sections = shelf(catalog.pieces, level: level, query: query)
            List {
                Group {
                    // Headers are plain rows, not Section headers: those pin while scrolling and pad themselves.
                    ForEach(sections, id: \.0) { category, rows in
                        sectionHeader(category.title, count: rows.map(\.pieceCount).reduce(0, +))
                        ForEach(rows) { row in
                            link(to: row)
                        }
                    }
                    if sections.isEmpty {
                        Text("没有找到").font(.subheadline).foregroundStyle(Theme.muted)
                            .frame(maxWidth: .infinity).padding(.top, Theme.Space.wider)
                    }
                }
                .cardRow()
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .background(Theme.ground)
            // Pinned under the search bar, so the level can change anywhere in the list.
            .safeAreaInset(edge: .top, spacing: 0) {
                levels
                    .padding(.horizontal, Theme.Space.gutter)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.ground)
            }
            .searchable(
                text: $query, placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text("搜索 \(catalog.pieces.count) 首曲目"))
        case .failure:
            ContentUnavailableView("曲库无法打开", systemImage: "exclamationmark.triangle")
        case nil:
            Color.clear
        }
    }

    /// The card, leading to the score or to the series' own list.
    @ViewBuilder private func link(to row: ShelfRow) -> some View {
        switch row {
        case .piece(let piece): NavigationLink(value: piece) { PieceCard(row: row) }.cardLink()
        case .series(let series): NavigationLink(value: series) { PieceCard(row: row) }.cardLink()
        }
    }

    private var levels: some View {
        HStack(spacing: Theme.Space.small) {
            chip("全部", value: nil)
            ForEach(1...4, id: \.self) { chip(levelTitle($0), value: $0) }
        }
    }

    private func chip(_ title: LocalizedStringKey, value: Int?) -> some View {
        let isOn = level == value
        return Button {
            level = value
        } label: {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 13)
                .frame(minHeight: 32)
                .foregroundStyle(isOn ? Theme.onAccent : Theme.ink)
                .background(isOn ? Theme.accent : Color.clear, in: Capsule())
                .overlay { Capsule().strokeBorder(isOn ? Color.clear : Theme.rule, lineWidth: 1) }
                // The capsule is 32 pt; the tap area reaches 44.
                .padding(.vertical, 6)
                .contentShape(Rectangle())
        }
        .animation(.easeInOut(duration: 0.2), value: isOn)
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func sectionHeader(_ title: LocalizedStringKey, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(song.font(17, bold: true)).foregroundStyle(Theme.ink)
            Spacer()
            Text("\(count) 首").font(.footnote).foregroundStyle(Theme.muted)
        }
        .padding(.top, 10)
    }
}

func levelTitle(_ level: Int) -> LocalizedStringKey {
    switch level {
    case 1: "入门"
    case 2: "初级"
    case 3: "中级"
    default: "高级"
    }
}

extension ShelfRow {
    var pieceCount: Int {
        switch self {
        case .piece: 1
        case .series(let series): series.pieces.count
        }
    }
}

extension View {
    /// A card that opens something: no disclosure chevron, found by the UI test.
    func cardLink() -> some View {
        navigationLinkIndicatorVisibility(.hidden).accessibilityIdentifier("piece")
    }

    /// A list row on the page ground, edge to edge within the gutter, no separators.
    func cardRow() -> some View {
        listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 4, leading: Theme.Space.gutter, bottom: 4, trailing: Theme.Space.gutter))
    }
}

extension PieceCategory {
    var title: LocalizedStringKey {
        switch self {
        case .tones: "长音与音阶"
        case .etude: "练习曲"
        case .piece: "乐曲"
        }
    }
}
