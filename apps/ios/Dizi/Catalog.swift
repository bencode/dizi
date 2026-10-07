import Foundation
import ScoreKit

/// The bundled library (`Library/`, built by `npm run library`): which pieces there are and their scores.
struct Catalog: Decodable {
    let pieces: [Piece]

    static func bundled() throws -> Catalog {
        try JSONDecoder().decode(Catalog.self, from: Data(contentsOf: try libraryURL("catalog.json")))
    }
}

struct Piece: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let category: Category
    /// 1 入门 … 4 高级
    let level: Int
    let lesson: Int?
    /// As printed: `1=E`, `2/4`.
    let key: String
    let time: String

    func score() throws -> Score {
        try Score.decode(from: Data(contentsOf: try libraryURL("scores/\(id).json")))
    }
}

enum Category: String, Decodable, CaseIterable {
    case tones
    case etude
    case piece
}

enum LibraryError: Error {
    case missing(String)
}

private func libraryURL(_ path: String) throws -> URL {
    guard let library = Bundle.main.url(forResource: "Library", withExtension: nil) else {
        throw LibraryError.missing("Library")
    }
    return library.appending(path: path)
}
