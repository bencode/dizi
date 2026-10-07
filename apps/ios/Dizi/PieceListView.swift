import OSLog
import SwiftUI

private let logger = Logger(subsystem: "io.upivot.dizi", category: "library")

struct PieceListView: View {
    @State private var catalog: Result<Catalog, any Error>?

    var body: some View {
        content
            .navigationTitle("曲目")
            .navigationDestination(for: Piece.self) { piece in
                PieceDetailView(piece: piece)
            }
            .task {
                do {
                    catalog = .success(try Catalog.bundled())
                } catch {
                    logger.error("Cannot read the library: \(error, privacy: .public)")
                    catalog = .failure(error)
                }
            }
    }

    @ViewBuilder private var content: some View {
        switch catalog {
        case .success(let catalog):
            List {
                ForEach(Category.allCases, id: \.self) { category in
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
    let piece: Piece

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

extension Category {
    var title: LocalizedStringKey {
        switch self {
        case .tones: "长音与音阶"
        case .etude: "练习曲"
        case .piece: "乐曲"
        }
    }
}
