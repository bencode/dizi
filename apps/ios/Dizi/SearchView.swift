import ScoreKit
import SwiftUI

/// The search tab: every section of both tabs, narrowed by title, series or pinyin as you type; matching 词典
/// entries come first.
struct SearchView: View {
    @Environment(LibraryStore.self) private var library
    @State private var query = ""

    var body: some View {
        content
            .navigationTitle("搜索")
            .navigationBarTitleDisplayMode(.inline)
            .libraryDestinations()
    }

    @ViewBuilder private var content: some View {
        switch library.catalog {
        case .success(let catalog):
            let sections = shelf(catalog, kind: nil, level: nil, query: query)
            let found = entries(catalog.dictionary, matching: query)
            ShelfList(sections: sections) {
                if !found.isEmpty {
                    SectionHeader(title: Text("词典"), count: Text("\(found.count) 条"))
                    ForEach(found) { EntryLink(entry: $0, fingerings: catalog.dictionary.fingerings) }
                }
            }
            .overlay {
                if sections.isEmpty && found.isEmpty {
                    ContentUnavailableView.search(text: query).foregroundStyle(Theme.muted)
                }
            }
            .searchable(text: $query, prompt: Text("搜索曲目和词典"))
        case .failure:
            unavailable("曲库无法打开", detail: "请稍后重新打开应用")
        case nil:
            Color.clear
        }
    }
}
