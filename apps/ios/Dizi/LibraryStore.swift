import Foundation
import OSLog
import ScoreKit

private let logger = Logger(subsystem: "io.upivot.dizi", category: "library")

/// The library on this phone (docs/library.md): the bundled snapshot, the published library cached in
/// Application Support, and the download that keeps the cache current. The decisions are ScoreKit's.
@Observable @MainActor final class LibraryStore {
    private(set) var catalog: Result<LibraryCatalog, any Error>?

    private static let remote = URL(string: "https://g.upivot.cn/upivot-dizi/library/catalog.json")!
    private let bundled = Bundle.main.url(forResource: "Library", withExtension: nil)
    private let cached = URL.applicationSupportDirectory.appending(path: "Library")

    /// Shows the newest of the bundled and the cached catalog.
    func load() {
        let shown = newest(readCatalog(in: cached), readCatalog(in: bundled))
        catalog = shown.map(Result.success) ?? .failure(CocoaError(.fileReadNoSuchFile))
    }

    /// Adopts the published catalog when it is newer: downloads its missing scores, then switches to it.
    func refresh() async {
        do {
            let data = try await fetched(Self.remote)
            let latest = try LibraryCatalog.decode(from: data)
            guard latest.updated > ((try? catalog?.get())?.updated ?? 0) else { return }
            for path in missingScores(latest, available: availableScores()) {
                let score = try await fetched(Self.remote.deletingLastPathComponent().appending(path: path))
                _ = try Score.decode(from: score)  // a score this app cannot read is not cached
                try write(score, to: path)
            }
            try write(data, to: "catalog.json")
            catalog = .success(latest)
            removeScores(unusedScores(cached: scores(in: cached), catalog: latest))
            logger.info("Library updated to \(latest.updated, privacy: .public)")
        } catch {
            logger.error("Library not updated: \(error, privacy: .public)")
        }
    }

    /// A piece's score, from the cache or else the bundle.
    func score(for piece: LibraryPiece) throws -> Score {
        let file = [cached, bundled].compactMap { $0?.appending(path: piece.score) }
            .first { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
        guard let file else { throw CocoaError(.fileReadNoSuchFile) }
        return try Score.decode(from: Data(contentsOf: file))
    }

    /// A file's body; any answer but 200 OK is a failure.
    private func fetched(_ url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        return data
    }

    private func readCatalog(in folder: URL?) -> LibraryCatalog? {
        guard let file = folder?.appending(path: "catalog.json"),
            FileManager.default.fileExists(atPath: file.path(percentEncoded: false))
        else { return nil }
        do {
            return try LibraryCatalog.decode(from: Data(contentsOf: file))
        } catch {
            logger.error(
                "Cannot read \(file.path(percentEncoded: false), privacy: .public): \(error, privacy: .public)")
            return nil
        }
    }

    private func availableScores() -> Set<String> {
        scores(in: cached).union(scores(in: bundled))
    }

    /// The score files in a library folder, as catalog paths (`scores/<hash>.json`).
    private func scores(in folder: URL?) -> Set<String> {
        guard let folder else { return [] }
        let names =
            (try? FileManager.default.contentsOfDirectory(
                atPath: folder.appending(path: "scores").path(percentEncoded: false))) ?? []
        return Set(names.map { "scores/\($0)" })
    }

    private func write(_ data: Data, to path: String) throws {
        let file = cached.appending(path: path)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
        var library = cached
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try library.setResourceValues(values)
    }

    private func removeScores(_ paths: Set<String>) {
        for path in paths {
            do {
                try FileManager.default.removeItem(at: cached.appending(path: path))
            } catch {
                logger.error("Cannot remove \(path, privacy: .public): \(error, privacy: .public)")
            }
        }
    }
}
