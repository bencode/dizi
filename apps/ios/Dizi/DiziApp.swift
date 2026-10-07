import SwiftUI

@main
struct DiziApp: App {
    @State private var library = LibraryStore()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                PieceListView()
            }
            .environment(library)
        }
    }
}
