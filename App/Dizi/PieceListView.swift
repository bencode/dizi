import SwiftUI

/// Stands in for real pieces until the library exists.
struct PlaceholderPiece: Identifiable, Hashable {
    let id: String
    let title: String
}

private let placeholderPieces = [
    PlaceholderPiece(id: "long-tones", title: "长音练习"),
    PlaceholderPiece(id: "d-major-scale", title: "D 调音阶"),
    PlaceholderPiece(id: "molihua", title: "茉莉花"),
]

struct PieceListView: View {
    var body: some View {
        List(placeholderPieces) { piece in
            NavigationLink(piece.title, value: piece)
        }
        .navigationTitle("曲目")
        .navigationDestination(for: PlaceholderPiece.self) { piece in
            PieceDetailView(piece: piece)
        }
    }
}
