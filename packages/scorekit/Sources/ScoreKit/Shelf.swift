import Foundation

/// Pieces of one series shown as one card: 双吐练习 with its 4 pieces.
public struct PieceSeries: Hashable, Sendable {
    public let name: String
    public let pieces: [LibraryPiece]

    /// The earliest stage among its pieces.
    public var level: Stage { pieces.map(\.level).min() ?? .beginner }
    /// The first lesson it comes from, if any piece has one.
    public var firstLesson: Int? { pieces.compactMap(\.lesson).min() }
}

/// One card in the list: a piece, or a series folded into one.
public enum ShelfRow: Hashable, Sendable, Identifiable {
    case piece(LibraryPiece)
    case series(PieceSeries)

    public var id: String {
        switch self {
        case .piece(let piece): piece.id
        case .series(let series): "series:\(series.name)"
        }
    }
}

/// The list as shown: per section of the catalog (empty ones dropped), the pieces matching `level` (nil = all)
/// and `query`, each series with two or more matches folded into one row at its first member.
public func shelf(_ catalog: LibraryCatalog, level: Stage?, query: String) -> [(LibrarySection, [ShelfRow])] {
    let needle = query.trimmingCharacters(in: .whitespaces)
    let matching = catalog.pieces.filter { piece in
        (level == nil || piece.level == level) && (needle.isEmpty || matches(piece, needle))
    }
    let members = Dictionary(grouping: matching.filter { $0.series != nil }) { $0.series ?? "" }
    let rows = matching.compactMap { piece -> (String, ShelfRow)? in
        guard let name = piece.series, let group = members[name], group.count > 1 else {
            return (piece.section, .piece(piece))
        }
        // The series takes the place of its first member; the others are inside it.
        return group.first == piece ? (piece.section, .series(PieceSeries(name: name, pieces: group))) : nil
    }
    return catalog.sections.compactMap { section in
        let inSection = rows.filter { $0.0 == section.id }.map(\.1)
        return inSection.isEmpty ? nil : (section, inSection)
    }
}

/// The title, the series, or the pinyin id contains the query, ignoring case.
private func matches(_ piece: LibraryPiece, _ query: String) -> Bool {
    [piece.title, piece.series ?? "", piece.id].contains { $0.localizedCaseInsensitiveContains(query) }
}
