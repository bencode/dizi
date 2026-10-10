import Foundation
import Testing

@testable import ScoreKit

private func catalog(updated: Int, scores: [String], version: Int = 1) throws -> LibraryCatalog {
    let pieces = scores.enumerated().map { index, score in
        #"{"id":"p\#(index)","title":"曲\#(index)","section":"pieces","level":1,"#
            + #""key":"1=D","time":"2/4","score":"\#(score)"}"#
    }
    let json =
        #"{"irVersion":\#(version),"updated":\#(updated),"sections":[{"id":"pieces","title":"乐曲"}],"#
        + #""pieces":[\#(pieces.joined(separator: ","))]}"#
    return try LibraryCatalog.decode(from: Data(json.utf8))
}

@Test func showsTheMostRecentlyUpdatedCatalog() throws {
    let bundled = try catalog(updated: 100, scores: ["scores/a.json"])
    let cached = try catalog(updated: 200, scores: ["scores/b.json"])

    let available: Set = ["scores/a.json", "scores/b.json"]

    #expect(newest(bundled, cached, available: available) == cached)
    #expect(newest(bundled, nil, available: available) == bundled)
    #expect(newest(cached, try catalog(updated: 200, scores: []), available: available) == cached)
    // A newer catalog whose score is not on the phone gives way to a complete one.
    #expect(newest(bundled, cached, available: ["scores/a.json"]) == bundled)
}

@Test func ignoresACatalogOfANewerScoreFormat() {
    #expect(throws: LibraryError.unsupportedVersion(2)) {
        try catalog(updated: 1, scores: [], version: 2)
    }
}

@Test func findsTheScoresToDownloadAndToDelete() throws {
    let latest = try catalog(updated: 1, scores: ["scores/a.json", "scores/b.json"])

    #expect(missingScores(latest, available: ["scores/a.json"]) == ["scores/b.json"])
    #expect(unusedScores(cached: ["scores/a.json", "scores/old.json"], catalog: latest) == ["scores/old.json"])
}

/// A catalog with three sections, in this order: scales, tonguing, pieces.
private func library(_ pieces: [String]) throws -> LibraryCatalog {
    let sections = #"[{"id":"scales","title":"音阶与指法"},{"id":"tonguing","title":"吐音"},{"id":"pieces","title":"乐曲"}]"#
    let json = #"{"irVersion":1,"updated":1,"sections":\#(sections),"pieces":[\#(pieces.joined(separator: ","))]}"#
    return try LibraryCatalog.decode(from: Data(json.utf8))
}

private func piece(_ id: String, _ section: String = "tonguing", level: Int = 1, series: String? = nil) -> String {
    let seriesField = series.map { #","series":"\#($0)""# } ?? ""
    return #"{"id":"\#(id)","title":"曲\#(id)","section":"\#(section)","level":\#(level)\#(seriesField),"#
        + #""key":"1=D","time":"2/4","score":"scores/\#(id).json"}"#
}

private func ids(_ rows: [ShelfRow]) -> [String] { rows.map(\.id) }

@Test func rejectsACatalogWithAPieceOutsideItsSections() {
    #expect(throws: LibraryError.unknownSection("etude")) {
        try library([piece("a", "etude")])
    }
}

@Test func foldsASeriesIntoOneRowAtItsFirstMember() throws {
    let catalog = try library([
        piece("a"), piece("shuangtu-1", series: "双吐"), piece("b"), piece("shuangtu-2", series: "双吐"),
    ])

    let shelved = shelf(catalog, level: nil, query: "")

    #expect(shelved.map(\.0.id) == ["tonguing"])
    #expect(ids(shelved[0].1) == ["a", "series:双吐", "b"])
    guard case .series(let series) = shelved[0].1[1] else { return }
    #expect(series.pieces.map(\.id) == ["shuangtu-1", "shuangtu-2"])
}

@Test func filtersByLevelAndPinyinAndUnfoldsASingleMatch() throws {
    let catalog = try library([
        piece("molihua", "pieces", level: 2), piece("yinjie", "scales", level: 1),
        piece("shuangtu-1", level: 1, series: "双吐"), piece("shuangtu-2", level: 2, series: "双吐"),
    ])

    // Sections keep the catalog's order, empty ones are dropped; a series with one match shows the piece itself.
    #expect(shelf(catalog, level: nil, query: "").map(\.0.id) == ["scales", "tonguing", "pieces"])
    #expect(shelf(catalog, level: .advanced, query: "").map(\.0.id) == ["tonguing", "pieces"])
    #expect(ids(shelf(catalog, level: .advanced, query: "")[0].1) == ["shuangtu-2"])
    #expect(ids(shelf(catalog, level: nil, query: " MoLi ").flatMap(\.1)) == ["molihua"])
    #expect(shelf(catalog, level: .beginner, query: "molihua").isEmpty)
}
