import Foundation
import Testing

@testable import ScoreKit

/// A dictionary with part of the fingering table from the course charts, and one entry.
private func dictionary(holes: String = "xxxxxx", category: String = "fingering") throws -> LibraryDictionary {
    let json = #"""
        {"categories": [{"id": "fingering", "title": "指法"}],
         "fingerings": [
           {"above": 0, "holes": "\#(holes)", "breath": "gentle"},
           {"above": 2, "holes": "xxxxxo", "breath": "gentle"},
           {"above": 3, "holes": "xxxxho", "breath": "gentle"},
           {"above": 10, "holes": "oxxooo", "breath": "gentle", "or": ["hooooo"]},
           {"above": 16, "holes": "xxxxoo", "breath": "strong"}],
         "entries": [{"id": "tongyin-5", "title": "筒音作5", "category": "\#(category)",
                      "aliases": ["全按作5", "zuo5"], "text": "…", "chart": {"degree": 5, "octave": -1}}]}
        """#
    return try JSONDecoder().decode(LibraryDictionary.self, from: Data(json.utf8))
}

private func row(_ rows: [ChartRow], _ degree: Int, _ octave: Int) -> ChartRow? {
    rows.first { $0.note == ChartNote(degree: degree, octave: octave) }
}

@Test func chartsFromTheTubeNoteUp() throws {
    let rows = chart(Fingering(degree: 5, octave: -1), fingerings: try dictionary().fingerings)

    // 5̣ is the tube note, all holes closed; 4 is the cross fingering, with its half-hole alternative.
    #expect(rows.first?.note == ChartNote(degree: 5, octave: -1))
    #expect(rows.first?.fingering?.holes == Array(repeating: .closed, count: 6))
    #expect(row(rows, 4, 0)?.fingering?.holes == [.open, .closed, .closed, .open, .open, .open])
    #expect(row(rows, 4, 0)?.fingering?.alternatives == [[.half, .open, .open, .open, .open, .open]])
    // 7̣ (4 semitones up) is not in this table: no fingering rather than a guess. 7 (16, 急吹) is the last row.
    #expect(row(rows, 7, -1) != nil && row(rows, 7, -1)?.fingering == nil)
    #expect(rows.last?.note == ChartNote(degree: 7, octave: 0))
    #expect(rows.last?.fingering?.breath == .strong)
}

@Test func givesFourAHalfHoleUnderTubeTwo() throws {
    let rows = chart(Fingering(degree: 2, octave: -1), fingerings: try dictionary().fingerings)

    #expect(row(rows, 4, -1)?.fingering?.holes == [.closed, .closed, .closed, .closed, .half, .open])
}

@Test func rejectsMalformedHolesAndStrayCategories() {
    #expect(throws: DecodingError.self) { try dictionary(holes: "xxxxx") }
    #expect(throws: LibraryError.unknownCategory("jiqiao")) { try dictionary(category: "jiqiao") }
}

@Test func findsEntriesByTitleOrPinyin() throws {
    let found = try dictionary()

    #expect(entries(found, matching: " ZUO5 ").map(\.id) == ["tongyin-5"])
    #expect(entries(found, matching: "作5").map(\.id) == ["tongyin-5"])
    #expect(entries(found, matching: "").isEmpty)
}
