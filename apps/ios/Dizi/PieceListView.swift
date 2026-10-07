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
            .task {
                library.load()
                await library.refresh()
            }
    }

    @ViewBuilder private var content: some View {
        switch library.catalog {
        case .success(let catalog):
            List {
                ForEach(PieceCategory.allCases, id: \.self) { category in
                    let pieces = catalog.pieces.filter { $0.category == category }
                    if !pieces.isEmpty {
                        Section(category.title) {
                            ForEach(pieces) { piece in
                                NavigationLink(value: piece) { PieceRow(piece: piece) }
                            }
                        }
                    }
                }
            }
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
            HStack(spacing: 8) {
                Text(verbatim: "\(piece.key)  \(piece.time)")
                if let lesson = piece.lesson {
                    Text("第\(lesson)课")
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
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
