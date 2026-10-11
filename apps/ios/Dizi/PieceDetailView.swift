import OSLog
import ScoreKit
import SwiftUI

private let logger = Logger(subsystem: "io.upivot.dizi", category: "score")

/// What a score page shows: a library piece, loaded from the library, or a personal score, already compiled.
enum PieceSource: Hashable {
    case library(LibraryPiece)
    case personal(PersonalPiece)
}

struct PieceDetailView: View {
    let source: PieceSource
    @Environment(LibraryStore.self) private var library
    @State private var loaded: Result<Player, any Error>?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        content
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            // The transport bar owns the bottom of the page.
            .toolbar(.hidden, for: .tabBar)
            .task { loaded = score.map { Player(pieceID: playerID, score: $0) } }
            .onChange(of: scenePhase) { _, phase in
                // Leaving the app (or a phone call) stops the audio; pause so the page is not left running.
                if phase != .active, case .success(let player) = loaded {
                    player.pause()
                }
            }
            // Hands are on the flute: the screen stays on while a run is playing or paused.
            .onChange(of: keepsAwake, initial: true) { _, awake in UIApplication.shared.isIdleTimerDisabled = awake }
            .onDisappear {
                UIApplication.shared.isIdleTimerDisabled = false
                if case .success(let player) = loaded {
                    player.stop()
                }
            }
    }

    private var title: String {
        switch source {
        case .library(let piece): piece.title
        case .personal(let piece): piece.title
        }
    }

    /// Keys the saved tempo; personal names are kept apart from library ids.
    private var playerID: String {
        switch source {
        case .library(let piece): piece.id
        case .personal(let piece): "personal.\(piece.name)"
        }
    }

    private var score: Result<Score, any Error> {
        switch source {
        case .library(let piece): loadScore(piece, from: library)
        case .personal(let piece): .success(piece.score)
        }
    }

    private var keepsAwake: Bool {
        guard case .success(let player) = loaded else { return false }
        if case .stopped = player.transport { return false }
        return true
    }

    @ViewBuilder private var content: some View {
        switch loaded {
        case .success(let player):
            // The score fills the page; the header and the controls float over it as bars.
            ScoreView(player: player)
                .safeAreaBar(edge: .top) { ScoreHeader(player: player) }
                .safeAreaBar(edge: .bottom) { TransportBar(player: player) }
                .background(Theme.ground)
                // The composer or origin under the title, as printed scores have it; an empty one shows nothing.
                .navigationSubtitle(Text(verbatim: player.score.meta.composer ?? ""))
        case .failure:
            unavailable("曲谱无法打开", detail: "这首曲谱的数据有误，请先练习其他曲目")
        case nil:
            Color.clear
        }
    }
}

@MainActor private func loadScore(_ piece: LibraryPiece, from library: LibraryStore) -> Result<Score, any Error> {
    do {
        return .success(try library.score(for: piece))
    } catch {
        logger.error("Cannot open score \(piece.id, privacy: .public): \(error, privacy: .public)")
        return .failure(error)
    }
}
