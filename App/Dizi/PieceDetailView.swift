import SwiftUI

struct PieceDetailView: View {
    let title: String

    var body: some View {
        Color.clear
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
    }
}
