import Foundation

/// A score in the IR format described in docs/score-ir.md.
/// Only the fields the app uses so far are decoded; the rest are ignored.
public struct Score: Decodable, Sendable {
    public let irVersion: Int
    public let meta: Meta
    public let header: Header
    public let ticksPerQuarter: Int
    public let measures: [Measure]
    public let parts: [Part]
    public let marks: [Mark]
    public let layoutHints: LayoutHints?

    public static func decode(from data: Data) throws -> Score {
        try JSONDecoder().decode(Score.self, from: data)
    }
}

public struct Meta: Decodable, Sendable {
    public let title: String?
    public let composer: String?
}

public struct Header: Decodable, Sendable {
    public let key: Key
}

public struct Key: Decodable, Sendable, Equatable {
    public let tonic: String
    public let accidental: Accidental?
}

public enum Accidental: String, Decodable, Sendable {
    case sharp
    case flat
}

public struct Measure: Decodable, Sendable {
    public let index: Int
    public let start: Int
    public let duration: Int
    public let time: TimeSignature
    public let barline: Barline
}

public enum TimeSignature: Decodable, Sendable, Equatable {
    case meter(beats: Int, unit: Int)
    /// 散板
    case free

    private struct Meter: Decodable {
        let beats: Int
        let unit: Int
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            guard text == "free" else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "Unknown time signature '\(text)'")
            }
            self = .free
        } else {
            let meter = try container.decode(Meter.self)
            self = .meter(beats: meter.beats, unit: meter.unit)
        }
    }
}

public enum Barline: String, Decodable, Sendable {
    case single
    case double
    case final
}

public struct Part: Decodable, Sendable {
    public let id: String
    public let role: String
    public let measures: [PartMeasure]
}

public struct PartMeasure: Decodable, Sendable {
    public let events: [Event]
    public let beams: [Beam]
}

/// Short notes joined per beat: one 减时线 in jianpu. `level` 1 = eighths, 2 = sixteenths.
public struct Beam: Decodable, Sendable {
    public let level: Int
    public let first: String
    public let last: String

    private enum CodingKeys: String, CodingKey {
        case level
        case first = "from"
        case last = "to"
    }
}

public enum Event: Decodable, Sendable {
    case note(Note)
    case rest(Rest)
    /// A kind this app does not know yet; skipped, so newer scores still open.
    case unknown

    private enum CodingKeys: String, CodingKey {
        case kind
    }

    public init(from decoder: any Decoder) throws {
        let kind = try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .kind)
        self =
            switch kind {
            case "note": .note(try Note(from: decoder))
            case "rest": .rest(try Rest(from: decoder))
            default: .unknown
            }
    }
}

public struct Note: Decodable, Sendable {
    public let id: String
    public let start: Int
    public let duration: Int
    /// Written value: 4 = quarter, 8 = eighth.
    public let value: Int
    public let dots: Int
    public let pitch: Pitch
}

public struct Rest: Decodable, Sendable {
    public let id: String
    public let start: Int
    public let duration: Int
    public let value: Int
    public let dots: Int
}

public struct Pitch: Decodable, Sendable {
    public let degree: Int
    public let accidental: Accidental?
    public let octave: Int
    public let semitones: Int
}

public enum Mark: Decodable, Sendable {
    case tempo(TempoMark)
    case section(SectionMark)
    /// A mark the app does not use yet.
    case other

    private enum CodingKeys: String, CodingKey {
        case kind
    }

    public init(from decoder: any Decoder) throws {
        let kind = try decoder.container(keyedBy: CodingKeys.self).decode(String.self, forKey: .kind)
        self =
            switch kind {
            case "tempo": .tempo(try TempoMark(from: decoder))
            case "section": .section(try SectionMark(from: decoder))
            default: .other
            }
    }
}

public struct TempoMark: Decodable, Sendable {
    public let tick: Int
    /// The beat's length in ticks: 480 for ♩, 720 for ♩.
    public let beat: Int
    public let bpm: BPM?
    public let text: String?

    private enum CodingKeys: String, CodingKey {
        case tick = "at"
        case beat, bpm, text
    }
}

/// 【一】, 引子, 散板 …: a new line starts here.
public struct SectionMark: Decodable, Sendable {
    public let tick: Int
    public let label: String

    private enum CodingKeys: String, CodingKey {
        case tick = "at"
        case label
    }
}

public enum BPM: Decodable, Sendable, Equatable {
    case exact(Int)
    case range(min: Int, max: Int)

    private struct Range: Decodable {
        let min: Int
        let max: Int
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            self = .exact(value)
        } else {
            let range = try container.decode(Range.self)
            self = .range(min: range.min, max: range.max)
        }
    }
}

public struct LayoutHints: Decodable, Sendable {
    public let lineBreaksAfter: [Int]
}
