import SwiftUI

@main
struct DiziApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                PieceListView()
            }
        }
    }
}
