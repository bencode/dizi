import Foundation

/// The library's catalog (docs/library.md): the pieces and where their scores are. The app bundles one, caches
/// the latest published one, and shows the newest.
public struct LibraryCatalog: Decodable, Sendable, Equatable {
    /// Unix seconds when the catalog was built or published.
    public let updated: Int
    public let pieces: [LibraryPiece]

    private enum CodingKeys: String, CodingKey {
        case irVersion, updated, pieces
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // The IR version this app reads; see Score.irVersion.
        let version = try container.decode(Int.self, forKey: .irVersion)
        guard version == 1 else { throw LibraryError.unsupportedVersion(version) }
        updated = try container.decode(Int.self, forKey: .updated)
        pieces = try container.decode([LibraryPiece].self, forKey: .pieces)
    }

    public static func decode(from data: Data) throws -> LibraryCatalog {
        try JSONDecoder().decode(LibraryCatalog.self, from: data)
    }
}

public struct LibraryPiece: Decodable, Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let category: PieceCategory
    /// 1 入门 … 4 高级
    public let level: Int
    public let lesson: Int?
    /// As printed: `1=E`, `2/4`.
    public let key: String
    public let time: String
    /// The score file, relative to the catalog: `scores/<hash>.json`.
    public let score: String
}

public enum PieceCategory: String, Decodable, Sendable, CaseIterable {
    case tones
    case etude
    case piece
}

public enum LibraryError: Error, Equatable {
    case unsupportedVersion(Int)
}

/// The catalog to show: the most recently updated one; the first wins a tie.
public func newest(_ catalogs: LibraryCatalog?...) -> LibraryCatalog? {
    catalogs.compactMap(\.self).reduce(nil) { best, catalog in
        best.map { $0.updated >= catalog.updated ? $0 : catalog } ?? catalog
    }
}

/// Score files the catalog needs that are not available locally, in catalog order.
public func missingScores(_ catalog: LibraryCatalog, available: Set<String>) -> [String] {
    catalog.pieces.map(\.score).filter { !available.contains($0) }
}

/// Cached score files the catalog no longer uses.
public func unusedScores(cached: Set<String>, catalog: LibraryCatalog) -> Set<String> {
    cached.subtracting(catalog.pieces.map(\.score))
}
