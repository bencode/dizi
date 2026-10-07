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
                Toggle("示范", isOn: $player.demoOn)
                    .toggleStyle(.button)
                    .disabled(!player.canDemo)
                Toggle("节拍", isOn: $player.clickOn)
                    .toggleStyle(.button)
            }
            .disabled(player.isRunning)
            HStack(spacing: 16) {
                Button(playTitle, systemImage: player.isRunning ? "pause.fill" : "play.fill") {
                    player.playOrPause()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!player.isRunning && !player.canPlay)
                Button("停止", systemImage: "stop.fill") {
                    player.stop()
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
        }
        .padding(16)
        .background(.bar)
    }

    private var playTitle: LocalizedStringKey { player.isRunning ? "暂停" : "开始" }

    private var tempo: some View {
        HStack(spacing: 4) {
            Button("减慢", systemImage: "minus") {
                player.bpm = max(Player.tempoRange.lowerBound, player.bpm - 1)
            }
            Text(verbatim: "♩=\(player.bpm)")
                .monospacedDigit()
                .frame(minWidth: 56)
            Button("加快", systemImage: "plus") {
                player.bpm = min(Player.tempoRange.upperBound, player.bpm + 1)
            }
        }
        .labelStyle(.iconOnly)
        .buttonRepeatBehavior(.enabled)
    }

    private func beatDots(_ beat: (index: Int, count: Int)?) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<(beat?.count ?? 0), id: \.self) { index in
                Circle()
                    .fill(index == beat?.index ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary.opacity(0.3)))
                    .frame(width: 10, height: 10)
            }
        }
        .frame(minHeight: 10)
    }
}
