import Foundation
import Testing

@testable import ScoreKit

private func catalog(updated: Int, scores: [String], version: Int = 1) throws -> LibraryCatalog {
    let pieces = scores.enumerated().map { index, score in
        #"{"id":"p\#(index)","title":"曲\#(index)","category":"piece","level":1,"#
            + #""key":"1=D","time":"2/4","score":"\#(score)"}"#
    }
    let json = #"{"irVersion":\#(version),"updated":\#(updated),"pieces":[\#(pieces.joined(separator: ","))]}"#
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

private func piece(_ id: String, _ category: String = "etude", level: Int = 2, series: String? = nil) throws
    -> LibraryPiece
{
    let seriesField = series.map { #","series":"\#($0)""# } ?? ""
    let json =
        #"{"id":"\#(id)","title":"曲\#(id)","category":"\#(category)","level":\#(level)\#(seriesField),"#
        + #""key":"1=D","time":"2/4","score":"scores/\#(id).json"}"#
    return try JSONDecoder().decode(LibraryPiece.self, from: Data(json.utf8))
}

private func ids(_ rows: [ShelfRow]) -> [String] { rows.map(\.id) }

@Test func foldsASeriesIntoOneRowAtItsFirstMember() throws {
    let pieces = [
        try piece("a"), try piece("shuangtu-1", series: "双吐"), try piece("b"),
        try piece("shuangtu-2", series: "双吐"),
    ]

    let shelved = shelf(pieces, level: nil, query: "")

    #expect(shelved.map(\.0) == [.etude])
    #expect(ids(shelved[0].1) == ["a", "series:双吐", "b"])
    guard case .series(let series) = shelved[0].1[1] else { return }
    #expect(series.pieces.map(\.id) == ["shuangtu-1", "shuangtu-2"])
}

@Test func filtersByLevelAndPinyinAndUnfoldsASingleMatch() throws {
    let pieces = [
        try piece("zizhudiao", "piece", level: 3), try piece("tones", "tones", level: 1),
        try piece("shuangtu-1", level: 2, series: "双吐"), try piece("shuangtu-2", level: 3, series: "双吐"),
    ]

    // Empty categories are dropped; a series with one match shows the piece itself.
    #expect(shelf(pieces, level: 3, query: "").map { $0.0 } == [.etude, .piece])
    #expect(ids(shelf(pieces, level: 3, query: "")[0].1) == ["shuangtu-2"])
    #expect(ids(shelf(pieces, level: nil, query: " ZiZhu ").flatMap(\.1)) == ["zizhudiao"])
    #expect(shelf(pieces, level: 4, query: "").isEmpty)
}
