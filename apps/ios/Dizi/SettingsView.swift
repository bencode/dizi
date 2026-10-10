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

/// 预备拍: whole bars of clicks before 走谱 starts.
enum CountIn: Int, CaseIterable, Identifiable {
    case none = 0
    case one = 1
    case two = 2

    static let key = "countIn"

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .none: "无"
        case .one: "一小节"
        case .two: "两小节"
        }
    }

    /// The stored choice; one bar until the player picks another.
    static var chosen: CountIn {
        UserDefaults.standard.object(forKey: key).flatMap { $0 as? Int }.flatMap(CountIn.init) ?? .one
    }
}

/// The app's settings, one section per topic.
struct SettingsView: View {
    @AppStorage("appearance") private var appearance: Appearance = .system
    @AppStorage(CountIn.key) private var countIn: CountIn = .one

    var body: some View {
        List {
            choices("外观", selection: $appearance)
            choices("预备拍", selection: $countIn, footer: "关掉节拍时，预备拍照样出声")
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.ground)
        .navigationTitle("设置")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// One topic: its options as rows, the chosen one checked in accent.
    private func choices<Choice: CaseIterable & Identifiable & Equatable>(
        _ title: LocalizedStringKey, selection: Binding<Choice>, footer: LocalizedStringKey? = nil
    ) -> some View where Choice.AllCases: RandomAccessCollection, Choice: Titled {
        Section {
            ForEach(Choice.allCases) { option in
                Button {
                    selection.wrappedValue = option
                } label: {
                    HStack {
                        Text(option.title).foregroundStyle(Theme.ink)
                        Spacer()
                        if option == selection.wrappedValue {
                            Image(systemName: "checkmark").foregroundStyle(Theme.accent)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(option == selection.wrappedValue ? .isSelected : [])
            }
            .listRowBackground(Theme.raised)
            .listRowSeparatorTint(Theme.rule)
        } header: {
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.ink)
                .textCase(nil)
        } footer: {
            if let footer {
                Text(footer).font(.footnote).foregroundStyle(Theme.muted)
            }
        }
    }
}

/// A setting's option with a title to show.
protocol Titled {
    var title: LocalizedStringKey { get }
}

extension Appearance: Titled {}
extension CountIn: Titled {}
