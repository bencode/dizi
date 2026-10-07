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
