import SwiftUI

@main
struct DiziApp: App {
    @State private var library = LibraryStore()
    @State private var song = SongFont()

    init() {
        styleNavigationBars(song: false)
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                PieceListView()
            }
            .environment(library)
            .environment(song)
            .tint(Theme.accent)
            // On the stack, not the list: the list's tasks restart each time a piece is closed.
            .task {
                library.load()
                await library.refresh()
            }
            .task { await song.load() }
            .onChange(of: song.isReady) { _, ready in styleNavigationBars(song: ready) }
        }
    }
}

/// Navigation titles in ink: Songti once it is on the phone, the serif before. UIKit owns the bar's title text, so
/// the appearance covers bars made later and the bars already on screen are restyled in place.
@MainActor private func styleNavigationBars(song: Bool) {
    let ink = UIColor(named: "Ink") ?? .label
    let font = { (size: CGFloat) in
        let base = UIFont.systemFont(ofSize: size, weight: .semibold)
        let serif = UIFont(descriptor: base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor, size: size)
        return song ? SongFont.uiFont(size) ?? serif : serif
    }
    // Inline titles only: a large title restyled in place is not redrawn.
    let title: [NSAttributedString.Key: Any] = [.foregroundColor: ink, .font: font(17)]
    let appearance = UINavigationBar.appearance()
    appearance.titleTextAttributes = title
    appearance.tintColor = ink
    let bars = UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap(\.windows)
        .flatMap { navigationBars(under: $0.rootViewController) }
    for bar in bars {
        bar.titleTextAttributes = title
    }
}

private func navigationBars(under controller: UIViewController?) -> [UINavigationBar] {
    guard let controller else { return [] }
    let own = (controller as? UINavigationController).map { [$0.navigationBar] } ?? []
    return own + controller.children.flatMap { navigationBars(under: $0) }
}
