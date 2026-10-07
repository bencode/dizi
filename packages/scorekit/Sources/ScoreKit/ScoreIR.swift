import Foundation

/// A score in the IR format described in docs/score-ir.md.
/// Only the fields the app uses so far are decoded; the rest are ignored.
public struct Score: Decodable, Sendable {
    public let irVersion: Int
    public let meta: Meta
    public let header: Header
    public let ticksPerQuarter: Int
    public let measures: [Measure]
    /// Measure indices in playing order, repeats unrolled.
    public let playOrder: [Int]
    public let parts: [Part]
    public let marks: [Mark]
    public let layoutHints: LayoutHints?

    public static func decode(from data: Data) throws -> Score {
        try JSONDecoder().decode(Score.self, from: data)
    }

    /// The tempo written at the very start, if any.
    public var startingTempo: TempoMark? {
        marks.lazy.compactMap(\.tempo).first { $0.tick == 0 }
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
    public let repeatStart: Bool
    public let repeatEnd: Bool
    /// The passes through a repeat this measure is played on (an ending: 1., 2.); nil outside endings.
    public let volta: [Int]?

    private enum CodingKeys: String, CodingKey {
        case index, start, duration, time, barline, repeatStart, repeatEnd, volta
    }

    /// The IR writes the repeat flags only when they are set.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        index = try container.decode(Int.self, forKey: .index)
        start = try container.decode(Int.self, forKey: .start)
        duration = try container.decode(Int.self, forKey: .duration)
        time = try container.decode(TimeSignature.self, forKey: .time)
        barline = try container.decode(Barline.self, forKey: .barline)
        repeatStart = try container.decodeIfPresent(Bool.self, forKey: .repeatStart) ?? false
        repeatEnd = try container.decodeIfPresent(Bool.self, forKey: .repeatEnd) ?? false
        volta = try container.decodeIfPresent([Int].self, forKey: .volta)
    }
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
    public let role: Role
    public let measures: [PartMeasure]
}

public enum Role: String, Decodable, Sendable {
    case solo
    case accompaniment
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
    public let value: NoteValue
    public let dots: Dots
    public let pitch: Pitch
}

public struct Rest: Decodable, Sendable {
    public let id: String
    public let start: Int
    public let duration: Int
    public let value: NoteValue
    public let dots: Dots
}

/// The written length; any other number fails decoding.
public enum NoteValue: Int, Decodable, Sendable {
    case whole = 1
    case half = 2
    case quarter = 4
    case eighth = 8
    case sixteenth = 16
    case thirtySecond = 32
    case sixtyFourth = 64
}

/// Augmentation dots (附点): none, one, or two.
public enum Dots: Int, Decodable, Sendable {
    case none = 0
    case single = 1
    case double = 2
}

public struct Pitch: Decodable, Sendable {
    /// 1...7; any other number fails decoding.
    public let degree: Int
    public let accidental: Accidental?
    public let octave: Int
    public let semitones: Int

    private enum CodingKeys: String, CodingKey {
        case degree, accidental, octave, semitones
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        degree = try container.decode(Int.self, forKey: .degree)
        guard (1...7).contains(degree) else {
            throw DecodingError.dataCorruptedError(
                forKey: .degree, in: container, debugDescription: "Degree \(degree) is not 1–7")
        }
        accidental = try container.decodeIfPresent(Accidental.self, forKey: .accidental)
        octave = try container.decode(Int.self, forKey: .octave)
        semitones = try container.decode(Int.self, forKey: .semitones)
    }
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

extension Mark {
    fileprivate var tempo: TempoMark? {
        guard case .tempo(let tempo) = self else { return nil }
        return tempo
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
