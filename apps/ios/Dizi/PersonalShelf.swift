import ScoreKit
import SwiftUI

/// 我的曲谱 at the top of the 乐曲 tab: a card per personal score, and a card per file that did not compile, saying
/// where. Nothing when there are no files.
struct PersonalShelf: View {
    @Environment(PersonalLibrary.self) private var personal

    var body: some View {
        if !personal.pieces.isEmpty || !personal.failures.isEmpty {
            SectionHeader(
                title: Text("我的曲谱"), count: Text("\(personal.pieces.count + personal.failures.count) 首"))
            ForEach(personal.pieces, id: \.name) { piece in
                NavigationLink(value: piece) {
                    CardLayout(title: piece.title) { Text(verbatim: headerText(piece.score)) }
                }
                .cardLink()
            }
            ForEach(personal.failures, id: \.name) { failure in
                CardLayout(title: failure.name) { problem(failure.error).foregroundStyle(Theme.accent) }
            }
        }
    }

    private func problem(_ error: Diagnostic?) -> Text {
        guard let error else { return Text("文件无法读取") }
        return Text("第 \(error.position.line) 行：\(error.message)")
    }
}
