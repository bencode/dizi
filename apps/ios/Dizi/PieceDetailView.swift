import OSLog
import ScoreKit
import SwiftUI

private let logger = Logger(subsystem: "io.upivot.dizi", category: "score")

struct PieceDetailView: View {
    let piece: LibraryPiece
    @Environment(LibraryStore.self) private var library
    @State private var loaded: Result<Player, any Error>?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        content
            .navigationTitle(piece.title)
            .navigationBarTitleDisplayMode(.inline)
            // The transport bar owns the bottom of the page.
            .toolbar(.hidden, for: .tabBar)
            .task { loaded = loadScore(piece, from: library).map { Player(pieceID: piece.id, score: $0) } }
            .onChange(of: scenePhase) { _, phase in
                // Leaving the app (or a phone call) stops the audio; pause so the page is not left running.
                if phase != .active, case .success(let player) = loaded {
                    player.pause()
                }
            }
            .onDisappear {
                if case .success(let player) = loaded {
                    player.stop()
                }
            }
    }

    @ViewBuilder private var content: some View {
        switch loaded {
        case .success(let player):
            // The score fills the page; the header and the controls float over it as bars.
            ScoreView(player: player)
                .safeAreaBar(edge: .top) { ScoreHeader(player: player) }
                .safeAreaBar(edge: .bottom) { TransportBar(player: player) }
                .background(Theme.ground)
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
