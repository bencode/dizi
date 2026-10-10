import ScoreKit
import SwiftUI

/// The 词典 tab: entries by category, each opening its own page.
struct DictionaryView: View {
    @Environment(LibraryStore.self) private var library

    var body: some View {
        content
            .navigationTitle("词典")
            .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder private var content: some View {
        switch library.catalog {
        case .success(let catalog) where !catalog.dictionary.entries.isEmpty:
            let dictionary = catalog.dictionary
            List {
                Group {
                    ForEach(dictionary.categories) { category in
                        let listed = dictionary.entries.filter { $0.category == category.id }
                        if !listed.isEmpty {
                            SectionHeader(title: Text(verbatim: category.title), count: Text("\(listed.count) 条"))
                            ForEach(listed) { EntryLink(entry: $0, fingerings: dictionary.fingerings) }
                        }
                    }
                }
                .cardRow()
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Theme.ground)
        case .success:
            unavailable("词典还没有内容", detail: "请稍后重新打开应用")
        case .failure:
            unavailable("曲库无法打开", detail: "请稍后重新打开应用")
        case nil:
            Color.clear
        }
    }
}

/// An entry's card: its title and its other names, opening the entry.
struct EntryLink: View {
    let entry: DictionaryEntry
    let fingerings: [Int: NoteFingering]
    @Environment(SongFont.self) private var song

    var body: some View {
        NavigationLink {
            EntryView(entry: entry, fingerings: fingerings)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: entry.title).font(song.font(17, relativeTo: .body)).foregroundStyle(Theme.ink)
                // The Chinese names; the pinyin ones are only for search.
                Text(verbatim: entry.aliases.filter { !$0.allSatisfy(\.isASCII) }.joined(separator: " · "))
                    .font(.footnote).foregroundStyle(Theme.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Theme.Space.medium)
            .padding(.horizontal, 14)
            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.rule, lineWidth: 1) }
            .accessibilityElement(children: .combine)
        }
        .navigationLinkIndicatorVisibility(.hidden)
        .accessibilityIdentifier("entry")
    }
}

/// One entry to read: its text, then its fingering chart if it has one.
struct EntryView: View {
    let entry: DictionaryEntry
    let fingerings: [Int: NoteFingering]

    var body: some View {
        List {
            Group {
                Text(verbatim: entry.text).foregroundStyle(Theme.ink).padding(.vertical, Theme.Space.small)
                if entry.chart != nil {
                    legend
                }
            }
            .cardRow()
            if let tube = entry.chart {
                ForEach(chart(tube, fingerings: fingerings)) { FingeringRow(row: $0) }
                    .cardRow()
            }
        }
        // Rows as tall as their content: every note gets the same gap, one hole line or two.
        .environment(\.defaultMinListRowHeight, 0)
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.ground)
        .navigationTitle(Text(verbatim: entry.title))
        .navigationBarTitleDisplayMode(.inline)
    }

    /// The legend's three kinds of hole.
    private var legendHoles: [(Hole, LocalizedStringKey)] { [(.closed, "按住"), (.open, "打开"), (.half, "半孔")] }

    private var legend: some View {
        HStack(spacing: Theme.Space.medium) {
            ForEach(legendHoles, id: \.0) { hole, title in
                HStack(spacing: Theme.Space.tiny) {
                    HoleMark(hole: hole)
                    Text(title)
                }
            }
            Spacer(minLength: 0)
            Text("吹孔在左")
        }
        .font(.footnote)
        .foregroundStyle(Theme.muted)
        .padding(.top, Theme.Space.small)
        .accessibilityElement(children: .combine)
    }
}

/// A chart row: the note, its six holes from the blow hole down, the breath, and any other way (或).
private struct FingeringRow: View {
    let row: ChartRow

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Space.large) {
            ChartNoteLabel(note: row.note).frame(width: 28)
            if let fingering = row.fingering {
                VStack(alignment: .leading, spacing: Theme.Space.small) {
                    holes(fingering.holes)
                    ForEach(fingering.alternatives, id: \.self) { alternative in
                        // 或 in front, in the gap after the note, so both hole rows line up.
                        holes(alternative).overlay(alignment: .leading) {
                            Text("或").font(.footnote).foregroundStyle(Theme.muted).fixedSize().offset(x: -22)
                        }
                    }
                }
                Spacer(minLength: 0)
                Text(breathTitle(fingering.breath)).font(.subheadline).foregroundStyle(Theme.muted)
            } else {
                Text(verbatim: "—").foregroundStyle(Theme.muted)
                Spacer(minLength: 0)
            }
        }
        // Holes and the 或 offset have fixed sizes; larger text would run into them.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private func holes(_ holes: [Hole]) -> some View {
        HStack(spacing: 7) {
            ForEach(holes.indices, id: \.self) { HoleMark(hole: holes[$0]) }
        }
        .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5 }
    }

    /// 中音5，按 2、3 孔，急吹, with 或 and the other way.
    private var spoken: String {
        let note = String(localized: octaveTitle(row.note.octave)) + "\(row.note.degree)"
        guard let fingering = row.fingering else { return note }
        let ways = ([fingering.holes] + fingering.alternatives).map(spokenHoles).joined(
            separator: String(localized: "；或"))
        return [note, ways, String(localized: breathTitle(fingering.breath))].joined(separator: "，")
    }
}

/// A jianpu digit with its octave dots: above for higher, below for lower.
private struct ChartNoteLabel: View {
    let note: ChartNote

    var body: some View {
        // The dots sit outside the digit and take no height, so every row is as tall as its holes.
        Text(verbatim: "\(note.degree)").font(Theme.serif(22)).foregroundStyle(Theme.ink)
            .overlay(alignment: .top) { dots(max(note.octave, 0)).alignmentGuide(.top) { $0[.bottom] - 3 } }
            .overlay(alignment: .bottom) { dots(max(-note.octave, 0)).alignmentGuide(.bottom) { $0[.top] + 2 } }
    }

    private func dots(_ count: Int) -> some View {
        VStack(spacing: 2) {
            ForEach(0..<count, id: \.self) { _ in Circle().fill(Theme.ink).frame(width: 4, height: 4) }
        }
    }
}

/// A finger hole: filled when closed, a ring when open, half filled when half closed.
private struct HoleMark: View {
    let hole: Hole

    var body: some View {
        ZStack {
            Circle().strokeBorder(Theme.ink, lineWidth: 1.5)
            switch hole {
            case .closed: Circle().fill(Theme.ink)
            case .open: EmptyView()
            case .half: Circle().fill(Theme.ink).mask(alignment: .leading) { Rectangle().frame(width: 8) }
            }
        }
        .frame(width: 16, height: 16)
    }
}

private func breathTitle(_ breath: Breath) -> LocalizedStringResource {
    switch breath {
    case .gentle: "缓吹"
    case .strong: "急吹"
    case .over: "超吹"
    }
}

private func octaveTitle(_ octave: Int) -> LocalizedStringResource {
    switch octave {
    case ..<0: "低音"
    case 0: "中音"
    case 1: "高音"
    default: "倍高音"
    }
}

/// The holes in words: 全按, 全开, or 按 1、2、3 孔 with 半按 5 孔.
private func spokenHoles(_ holes: [Hole]) -> String {
    let numbered = { (kind: Hole) in
        holes.indices.filter { holes[$0] == kind }.map { String($0 + 1) }.joined(separator: "、")
    }
    // Counted from the blow hole, as drawn: textbooks number the holes either way.
    if holes.allSatisfy({ $0 == .closed }) { return String(localized: "全按") }
    let closed = numbered(.closed)
    let half = numbered(.half)
    let parts = [
        closed.isEmpty ? (half.isEmpty ? String(localized: "全开") : nil) : String(localized: "从吹孔数起，按 \(closed) 孔"),
        half.isEmpty ? nil : String(localized: "半按 \(half) 孔"),
    ]
    return parts.compactMap(\.self).joined(separator: "，")
}
