import Foundation

/// The 词典 (docs/library.md): entries to look up, and the fingering table their charts are drawn from. Content, so
/// it is data published with the library, not app code.
public struct LibraryDictionary: Decodable, Sendable, Equatable {
    /// In display order.
    public let categories: [DictionaryCategory]
    public let entries: [DictionaryEntry]
    /// Keyed by semitones above the tube note (筒音): a fingering depends only on that distance.
    public let fingerings: [Int: NoteFingering]

    public static let empty = LibraryDictionary(categories: [], entries: [], fingerings: [:])

    private init(categories: [DictionaryCategory], entries: [DictionaryEntry], fingerings: [Int: NoteFingering]) {
        self.categories = categories
        self.entries = entries
        self.fingerings = fingerings
    }

    private enum CodingKeys: String, CodingKey {
        case categories, entries, fingerings
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        categories = try container.decode([DictionaryCategory].self, forKey: .categories)
        entries = try container.decode([DictionaryEntry].self, forKey: .entries)
        let rows = try container.decode([FingeringSource].self, forKey: .fingerings)
        fingerings = Dictionary(
            rows.map {
                (
                    $0.above,
                    NoteFingering(
                        holes: $0.holes.holes, breath: $0.breath, alternatives: $0.alternatives?.map(\.holes) ?? [])
                )
            },
            uniquingKeysWith: { first, _ in first })
        // Every entry is listed somewhere; a dictionary that breaks this rejects the catalog whole.
        let known = Set(categories.map(\.id))
        if let stray = entries.first(where: { !known.contains($0.category) }) {
            throw LibraryError.unknownCategory(stray.category)
        }
    }
}

public struct DictionaryCategory: Decodable, Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
}

public struct DictionaryEntry: Decodable, Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    /// The id of the category it is listed in.
    public let category: String
    /// Other names and pinyin, for search: 全按作5, zuo5.
    public let aliases: [String]
    public let text: String
    /// When set, the entry shows the chart of this 筒音 (the IR's fingering: 筒音作5̣ is degree 5, octave -1).
    public let chart: Fingering?
}

/// How to play one pitch: the six finger holes from the blow hole down, the breath, and other ways (或).
public struct NoteFingering: Sendable, Hashable {
    public let holes: [Hole]
    public let breath: Breath
    public let alternatives: [[Hole]]
}

public enum Hole: Sendable, Hashable {
    case closed, open, half
}

/// 缓吹, 急吹, 超吹: the low, middle and high register.
public enum Breath: String, Decodable, Sendable, Hashable {
    case gentle, strong, over
}

/// A row of the published fingering table: `{ above, holes, breath, or }`.
private struct FingeringSource: Decodable {
    let above: Int
    let holes: Holes
    let breath: Breath
    let alternatives: [Holes]?

    private enum CodingKeys: String, CodingKey {
        case above, holes, breath
        case alternatives = "or"
    }
}

/// Six holes written as x (closed), o (open), h (half); any other text does not decode.
private struct Holes: Decodable {
    let holes: [Hole]

    init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        let holes = text.compactMap { mark -> Hole? in
            switch mark {
            case "x": .closed
            case "o": .open
            case "h": .half
            default: nil
            }
        }
        guard holes.count == 6, text.count == 6 else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "Expected six of x, o, h: \(text)"))
        }
        self.holes = holes
    }
}

/// A note of a fingering chart, as jianpu writes it: a degree and its octave dots.
public struct ChartNote: Sendable, Hashable {
    public let degree: Int
    public let octave: Int
}

public struct ChartRow: Sendable, Hashable, Identifiable {
    public let note: ChartNote
    /// Nil where the table has no fingering from a source: shown as none, never guessed.
    public let fingering: NoteFingering?

    public var id: ChartNote { note }
}

/// The chart of a tube: every scale degree from the tube note up to the table's highest pitch, low to high.
public func chart(_ tube: Fingering, fingerings: [Int: NoteFingering]) -> [ChartRow] {
    let major = [0, 2, 4, 5, 7, 9, 11]
    let semitones = { (degree: Int, octave: Int) in major[degree - 1] + 12 * octave }
    let base = semitones(tube.degree, tube.octave)
    guard let highest = fingerings.keys.max() else { return [] }
    let octaves = tube.octave...(tube.octave + highest / 12 + 1)
    return octaves.flatMap { octave in (1...7).map { ChartNote(degree: $0, octave: octave) } }
        .map { (note: $0, above: semitones($0.degree, $0.octave) - base) }
        .filter { (0...highest).contains($0.above) }
        .map { ChartRow(note: $0.note, fingering: fingerings[$0.above]) }
}

/// Entries whose title or an alias contains the query, ignoring case; none for an empty query.
public func entries(_ dictionary: LibraryDictionary, matching query: String) -> [DictionaryEntry] {
    let needle = query.trimmingCharacters(in: .whitespaces)
    guard !needle.isEmpty else { return [] }
    return dictionary.entries.filter { entry in
        ([entry.title] + entry.aliases).contains { $0.localizedCaseInsensitiveContains(needle) }
    }
}
