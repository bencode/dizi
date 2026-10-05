import Foundation
import Testing

@testable import ScoreKit

/// A one-note score; each argument replaces one field so a test can make exactly that field invalid.
private func oneNote(value: String = "4", dots: String = "0", degree: String = "5", role: String = "\"solo\"") -> Data {
    let json = """
        {"irVersion": 1, "meta": {}, "header": {"key": {"tonic": "D"}}, "ticksPerQuarter": 480,
         "measures": [{"index": 0, "start": 0, "duration": 480, "time": "free", "barline": "final"}],
         "playOrder": [0],
         "parts": [{"id": "solo", "role": \(role), "measures": [{"events": [
            {"kind": "note", "id": "n1", "start": 0, "duration": 480, "value": \(value), "dots": \(dots),
             "pitch": {"degree": \(degree), "octave": 0, "semitones": 7}}], "beams": []}]}],
         "spans": [], "marks": []}
        """
    return Data(json.utf8)
}

@Test func decodesAValidNote() throws {
    #expect(throws: Never.self) { try Score.decode(from: oneNote()) }
}

@Test(arguments: [
    oneNote(value: "3"),
    oneNote(dots: "3"),
    oneNote(degree: "8"),
    oneNote(degree: "0"),
    oneNote(role: "\"duet\""),
])
func rejectsAnInvalidScore(_ data: Data) {
    #expect(throws: DecodingError.self) { try Score.decode(from: data) }
}
