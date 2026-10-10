import SwiftUI

@main
struct DiziApp: App {
    @State private var library = LibraryStore()
    @AppStorage("appearance") private var appearance: Appearance = .system

    init() {
        styleNavigationBars()
    }

    var body: some Scene {
        WindowGroup {
            TabView {
                Tab("练习", systemImage: "metronome") { NavigationStack { PieceListView(kind: .practice) } }
                Tab("乐曲", systemImage: "music.note") { NavigationStack { PieceListView(kind: .repertoire) } }
                Tab("词典", systemImage: "book.closed") { NavigationStack { DictionaryView() } }
                Tab(role: .search) { NavigationStack { SearchView() } }
            }
            .tabBarMinimizeBehavior(.onScrollDown)
            // Search as the system's own trailing circle: tapping it opens the field; on iOS 27 only a tab that
            // activates search gets that place.
            .tabViewSearchActivation(.searchTabSelection)
            .environment(library)
            .tint(Theme.accent)
            // On the tabs, not a list: they run once, and a list's tasks restart each time a piece is closed.
            .task {
                library.load()
                await library.refresh()
            }
            .task { apply(appearance) }
            .onChange(of: appearance) { _, chosen in apply(chosen) }
        }
    }
}

/// Navigation titles and buttons in ink, in the system font. UIKit owns the bar's title text, so this is set on the
/// appearance before any bar exists.
@MainActor private func styleNavigationBars() {
    let ink = UIColor(named: "Ink") ?? .label
    let appearance = UINavigationBar.appearance()
    appearance.titleTextAttributes = [.foregroundColor: ink]
    appearance.tintColor = ink
}

/// The chosen appearance on every window. UIKit's override, not `.preferredColorScheme`: it returns cleanly to
/// following the phone and restyles the bars with the content.
@MainActor private func apply(_ appearance: Appearance) {
    for window in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).flatMap(\.windows) {
        window.overrideUserInterfaceStyle = appearance.style
    }
}
