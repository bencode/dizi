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
            // On the stack, not the list: the list's tasks restart each time a piece is closed.
            .task {
                library.load()
                await library.refresh()
            }
        }
    }
}
