import OSLog
import ScoreKit
import SwiftUI

private let logger = Logger(subsystem: "io.upivot.dizi", category: "score")

struct PieceDetailView: View {
    let piece: PlaceholderPiece
    @State private var loaded: Result<Player, any Error>?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        content
            .navigationTitle(piece.title)
            .navigationBarTitleDisplayMode(.inline)
            .task { loaded = loadScore(id: piece.id).map { $0.map { Player(pieceID: piece.id, score: $0) } } }
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

/// Nil when the piece has no bundled score yet (placeholders); a failure when the score cannot be read.
private func loadScore(id: String) -> Result<Score, any Error>? {
    guard let url = Bundle.main.url(forResource: "\(id).ir", withExtension: "json") else { return nil }
    do {
        return .success(try Score.decode(from: Data(contentsOf: url)))
    } catch {
        logger.error("Cannot open score \(id, privacy: .public): \(error, privacy: .public)")
        return .failure(error)
    }
}
