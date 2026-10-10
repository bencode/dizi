import Foundation

/// The library's catalog (docs/library.md): the list's sections, the pieces and where their scores are. The app
/// bundles one, caches the latest published one, and shows the newest.
public struct LibraryCatalog: Decodable, Sendable, Equatable {
    /// Unix seconds when the catalog was built or published.
    public let updated: Int
    /// In display order.
    public let sections: [LibrarySection]
    public let pieces: [LibraryPiece]

    private enum CodingKeys: String, CodingKey {
        case irVersion, updated, sections, pieces
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // The IR version this app reads; see Score.irVersion.
        let version = try container.decode(Int.self, forKey: .irVersion)
        guard version == 1 else { throw LibraryError.unsupportedVersion(version) }
        updated = try container.decode(Int.self, forKey: .updated)
        sections = try container.decode([LibrarySection].self, forKey: .sections)
        pieces = try container.decode([LibraryPiece].self, forKey: .pieces)
        // Every piece is listed somewhere; a catalog that breaks this is rejected whole.
        let known = Set(sections.map(\.id))
        if let stray = pieces.first(where: { !known.contains($0.section) }) {
            throw LibraryError.unknownSection(stray.section)
        }
    }

    public static func decode(from data: Data) throws -> LibraryCatalog {
        try JSONDecoder().decode(LibraryCatalog.self, from: data)
    }
}

public struct LibraryPiece: Decodable, Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    /// The id of the section it is listed in.
    public let section: String
    public let level: Stage
    public let lesson: Int?
    /// Pieces sharing a series fold into one card: 双吐练习.
    public let series: String?
    /// As printed: `1=E`, `2/4`.
    public let key: String
    public let time: String
    /// The score file, relative to the catalog: `scores/<hash>.json`.
    public let score: String
}

/// The course's two stages; a catalog with any other level does not decode.
public enum Stage: Int, Decodable, Sendable, Hashable, Comparable, CaseIterable {
    /// 入门: the course's part a.
    case beginner = 1
    /// 进阶: the course's part b.
    case advanced = 2

    public static func < (lhs: Stage, rhs: Stage) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// A group of the list: 吐音, 乐曲. Its title and place are data, so a new group needs no app release.
public struct LibrarySection: Decodable, Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
}

public enum LibraryError: Error, Equatable {
    case unsupportedVersion(Int)
    case unknownSection(String)
}

/// The catalog to show: the most recently updated one whose scores are all available; the first wins a tie.
public func newest(_ catalogs: LibraryCatalog?..., available: Set<String>) -> LibraryCatalog? {
    let complete = catalogs.compactMap(\.self).filter { missingScores($0, available: available).isEmpty }
    return complete.reduce(nil) { best, catalog in
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
