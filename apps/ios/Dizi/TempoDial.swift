import SwiftUI

/// The tempo panel opened from the header: the tempo large, a ruler swiped left and right with a tick per step,
/// and 原速 to return to the written tempo.
struct TempoDial: View {
    @Bindable var player: Player
    /// The value under the centre line, as the ruler scrolls.
    @State private var centred: Int?

    private static let step: CGFloat = 10
    private static let width: CGFloat = 264

    var body: some View {
        VStack(spacing: Theme.Space.large) {
            Text(verbatim: "\(symbol)\(player.bpm)")
                .font(Theme.serif(34))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
            ruler
            Button("原速 \(symbol)\(player.writtenBPM)") { player.bpm = player.writtenBPM }
                .buttonStyle(Switch(isOn: false))
                .disabled(player.bpm == player.writtenBPM)
        }
        .padding(Theme.Space.large)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .presentationBackground(Theme.raised)
    }

    private var symbol: String { beatSymbol(player.score.startingTempo?.beat) }

    private var ruler: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: 0) {
                ForEach(Player.tempoRange, id: \.self) { tick($0) }
            }
            .scrollTargetLayout()
        }
        // The first and last values can reach the centre line.
        .contentMargins(.horizontal, (Self.width - Self.step) / 2, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
        .scrollPosition(id: $centred, anchor: .center)
        .frame(width: Self.width, height: 48)
        .overlay(alignment: .top) { Capsule().fill(Theme.accent).frame(width: 2, height: 30) }
        .mask { LinearGradient(colors: [.clear, .black, .black, .clear], startPoint: .leading, endPoint: .trailing) }
        .onAppear { centred = player.bpm }
        .onChange(of: centred) { _, value in
            if let value, value != player.bpm {
                player.bpm = value
            }
        }
        .onChange(of: player.bpm) { _, value in
            if centred != value {
                withAnimation { centred = value }
            }
        }
        .sensoryFeedback(.selection, trigger: player.bpm)
        // VoiceOver adjusts the tempo on the header instead.
        .accessibilityHidden(true)
    }

    /// One step: a short line, longer every 5, longest every 10 with its value underneath.
    private func tick(_ value: Int) -> some View {
        let height: CGFloat = value % 10 == 0 ? 22 : value % 5 == 0 ? 15 : 9
        return Rectangle()
            .fill(value % 10 == 0 ? Theme.ink : Theme.muted)
            .frame(width: 1, height: height)
            .frame(width: Self.step, height: 30, alignment: .top)
            .overlay(alignment: .bottom) {
                if value % 10 == 0 {
                    Text(verbatim: "\(value)").font(.caption2).monospacedDigit().foregroundStyle(Theme.muted)
                        .fixedSize().offset(y: 16)
                }
            }
    }
}
