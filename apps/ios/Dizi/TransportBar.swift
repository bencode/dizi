import ScoreKit
import SwiftUI

/// The controls under the score: beat, tempo, click switch, start/pause, stop.
struct TransportBar: View {
    @Bindable var player: Player

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                TimelineView(.animation(paused: !player.isRunning)) { _ in
                    beatDots(player.beatInBar)
                }
                Spacer()
                tempo
                Button("示范") { player.demoOn.toggle() }
                    .buttonStyle(Pill(isOn: player.demoOn))
                    .accessibilityAddTraits(player.demoOn ? .isSelected : [])
                    .disabled(!player.canDemo)
                Button("节拍") { player.clickOn.toggle() }
                    .buttonStyle(Pill(isOn: player.clickOn))
                    .accessibilityAddTraits(player.clickOn ? .isSelected : [])
            }
            .disabled(player.isRunning)
            HStack(spacing: 16) {
                Button(playTitle, systemImage: player.isRunning ? "pause.fill" : "play.fill") {
                    player.playOrPause()
                }
                .buttonStyle(Pill(isOn: true))
                .disabled(!player.isRunning && !player.canPlay)
                Button("停止", systemImage: "stop.fill") {
                    player.stop()
                }
                .buttonStyle(Pill(isOn: false))
            }
        }
        .padding(Theme.Space.large)
        .background(Theme.raised)
        .overlay(alignment: .top) { Theme.rule.frame(height: 1) }
    }

    private var playTitle: LocalizedStringKey { player.isRunning ? "暂停" : "开始" }

    private var tempo: some View {
        HStack(spacing: 4) {
            Button("减慢", systemImage: "minus") {
                player.bpm = max(Player.tempoRange.lowerBound, player.bpm - 1)
            }
            Text(verbatim: "♩=\(player.bpm)")
                .font(Theme.serif(19))
                .monospacedDigit()
                .foregroundStyle(Theme.ink)
                .frame(minWidth: 56)
            Button("加快", systemImage: "plus") {
                player.bpm = min(Player.tempoRange.upperBound, player.bpm + 1)
            }
        }
        .labelStyle(.iconOnly)
        .foregroundStyle(Theme.ink)
        .buttonRepeatBehavior(.enabled)
    }

    private func beatDots(_ beat: (index: Int, count: Int)?) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<(beat?.count ?? 0), id: \.self) { index in
                Circle()
                    .fill(index == beat?.index ? Theme.accent : Theme.muted.opacity(0.35))
                    .frame(width: 10, height: 10)
            }
        }
        .frame(minHeight: 10)
    }
}

/// A capsule button in the theme's colours: accent-filled when on, outlined in ink when off.
private struct Pill: ButtonStyle {
    let isOn: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
            .padding(.horizontal, Theme.Space.large)
            .frame(minHeight: 44)
            .foregroundStyle(isOn ? Theme.onAccent : Theme.ink)
            .background(isOn ? Theme.accent : Color.clear, in: Capsule())
            .overlay { Capsule().strokeBorder(isOn ? Color.clear : Theme.rule, lineWidth: 1) }
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
    }
}
