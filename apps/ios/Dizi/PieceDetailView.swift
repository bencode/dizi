import OSLog
import ScoreKit
import SwiftUI

private let logger = Logger(subsystem: "io.upivot.dizi", category: "score")

struct PieceDetailView: View {
    let piece: Piece
    @State private var loaded: Result<Player, any Error>?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        content
            .navigationTitle(piece.title)
            .navigationBarTitleDisplayMode(.inline)
            .task { loaded = loadScore(piece).map { Player(pieceID: piece.id, score: $0) } }
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
            VStack(spacing: 0) {
                ScoreView(player: player)
                TransportBar(player: player)
            }
        case .failure:
            ContentUnavailableView("曲谱无法打开", systemImage: "exclamationmark.triangle")
        case nil:
            Color.clear
        }
    }
}

private func loadScore(_ piece: Piece) -> Result<Score, any Error> {
    do {
        return .success(try piece.score())
    } catch {
        logger.error("Cannot open score \(piece.id, privacy: .public): \(error, privacy: .public)")
        return .failure(error)
    }
}
