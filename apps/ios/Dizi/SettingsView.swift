import SwiftUI

/// 外观: the user's choice; system follows the phone.
enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
        }
    }

    var style: UIUserInterfaceStyle {
        switch self {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
    }
}

/// The app's settings, one section per topic; 外观 is the first.
struct SettingsView: View {
    @AppStorage("appearance") private var appearance: Appearance = .system
    @Environment(SongFont.self) private var song

    var body: some View {
        List {
            Section {
                ForEach(Appearance.allCases) { option in
                    Button {
                        appearance = option
                    } label: {
                        HStack {
                            Text(option.title).foregroundStyle(Theme.ink)
                            Spacer()
                            if option == appearance {
                                Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(option == appearance ? .isSelected : [])
                }
                .listRowBackground(Theme.raised)
                .listRowSeparatorTint(Theme.rule)
            } header: {
                Text("外观")
                    .font(song.font(17, bold: true, relativeTo: .headline))
                    .foregroundStyle(Theme.ink)
                    .textCase(nil)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.ground)
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
    }
}
