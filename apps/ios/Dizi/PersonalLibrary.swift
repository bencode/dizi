import Foundation
import OSLog
import ScoreKit

private let logger = Logger(subsystem: "io.upivot.dizi", category: "personal")

/// 我的曲谱: the score files the player put in the app's Documents folder (visible in the Files app), compiled on
/// the phone. They never leave it.
@MainActor
@Observable
final class PersonalLibrary {
    private(set) var pieces: [PersonalPiece] = []
    private(set) var failures: [PersonalFailure] = []

    /// Made on first use; nil when the bundled parser is missing or broken.
    @ObservationIgnored private lazy var compiler: JianpuCompiler? = {
        do {
            guard let url = Bundle.main.url(forResource: "parser", withExtension: "js", subdirectory: "Parser") else {
                throw CocoaError(.fileReadNoSuchFile)
            }
            return try JianpuCompiler(script: String(contentsOf: url, encoding: .utf8))
        } catch {
            logger.error("Parser unavailable: \(error, privacy: .public)")
            return nil
        }
    }()

    /// Reads and compiles every `.jianpu` file in Documents again: at launch, and each time the app comes back,
    /// since the player edits them in the Files app.
    func reload() {
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(
                at: URL.documentsDirectory, includingPropertiesForKeys: [.contentModificationDateKey]
            ).filter { $0.pathExtension == "jianpu" }
        } catch {
            logger.error("Cannot list Documents: \(error, privacy: .public)")
            files = []
        }
        guard let compiler else { return }
        let read = files.map { read($0, with: compiler) }
        pieces = read.compactMap { if case .success(let piece) = $0 { piece } else { nil } }
            .sorted { inPinyinOrder($0.title, $1.title) }
        failures = read.compactMap { if case .failure(let failure) = $0 { failure } else { nil } }
            .sorted { inPinyinOrder($0.name, $1.name) }
    }

    private func read(_ file: URL, with compiler: JianpuCompiler) -> Result<PersonalPiece, PersonalFailure> {
        let name = file.deletingPathExtension().lastPathComponent
        do {
            let modified = try file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            switch try compiler.compile(String(contentsOf: file, encoding: .utf8)) {
            case .score(let score):
                return .success(
                    PersonalPiece(name: name, title: score.meta.title ?? name, score: score, modified: modified))
            case .failed(let errors):
                return .failure(PersonalFailure(name: name, error: errors.first))
            }
        } catch {
            logger.error("Cannot read \(name, privacy: .public): \(error, privacy: .public)")
            return .failure(PersonalFailure(name: name, error: nil))
        }
    }
}

/// Chinese titles in pinyin order (the zh-Hans collation), whatever language the phone is set to.
private func inPinyinOrder(_ lhs: String, _ rhs: String) -> Bool {
    lhs.compare(rhs, options: [.numeric], locale: Locale(identifier: "zh-Hans")) == .orderedAscending
}

/// A personal score that compiled. Equal while its file is unchanged, so it can be a navigation value.
struct PersonalPiece: Hashable {
    /// The file name without `.jianpu`.
    let name: String
    let title: String
    let score: Score
    let modified: Date?

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.name == rhs.name && lhs.modified == rhs.modified }
    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(modified)
    }
}

/// A personal score file that did not compile: its first error, or none when the file could not be read.
struct PersonalFailure: Error {
    let name: String
    let error: Diagnostic?
}
