import SwiftUI

@main
struct DiziApp: App {
    @State private var library = LibraryStore()

    init() {
        // Navigation titles in ink and serif, as the rest of the theme; UIKit owns the bar's title text.
        let ink = UIColor(named: "Ink") ?? .label
        let serif = { (size: CGFloat) in
            let base = UIFont.systemFont(ofSize: size, weight: .semibold)
            return UIFont(descriptor: base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor, size: size)
        }
        let appearance = UINavigationBar.appearance()
        appearance.titleTextAttributes = [.foregroundColor: ink, .font: serif(17)]
        appearance.largeTitleTextAttributes = [.foregroundColor: ink, .font: serif(34)]
        appearance.tintColor = ink
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                PieceListView()
            }
            .environment(library)
            .tint(Theme.accent)
            // On the stack, not the list: the list's tasks restart each time a piece is closed.
            .task {
                library.load()
                await library.refresh()
            }
        }
    }
}
