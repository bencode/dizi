import ScoreKit
import SwiftUI

struct PieceListView: View {
    @Environment(LibraryStore.self) private var library

    var body: some View {
        content
            .navigationTitle("曲目")
            .navigationDestination(for: LibraryPiece.self) { piece in
                PieceDetailView(piece: piece)
            }
    }

    @ViewBuilder private var content: some View {
        switch library.catalog {
        case .success(let catalog):
            List {
                ForEach(PieceCategory.allCases, id: \.self) { category in
                    let pieces = catalog.pieces.filter { $0.category == category }
                    if !pieces.isEmpty {
                        Section {
                            ForEach(pieces) { piece in
                                NavigationLink(value: piece) { PieceRow(piece: piece) }
                                    .listRowBackground(Theme.raised)
                                    .listRowSeparatorTint(Theme.rule)
                            }
                        } header: {
                            Text(category.title).font(Theme.serif(17, weight: .semibold)).foregroundStyle(Theme.ink)
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.ground)
        case .failure:
            ContentUnavailableView("曲库无法打开", systemImage: "exclamationmark.triangle")
        case nil:
            Color.clear
        }
    }
}

private struct PieceRow: View {
    let piece: LibraryPiece

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: piece.title)
                .font(Theme.serif(17))
                .foregroundStyle(Theme.ink)
            HStack(spacing: 8) {
                Text(verbatim: "\(piece.key)  \(piece.time)")
                if let lesson = piece.lesson {
                    Text("第\(lesson)课")
                }
            }
            .font(.footnote)
            .foregroundStyle(Theme.muted)
        }
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
