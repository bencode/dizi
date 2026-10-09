import ScoreKit
import SwiftUI

/// The controls under the score, in one row: the 示范 and 节拍 switches, the beat, then stop and start/pause.
struct TransportBar: View {
    @Bindable var player: Player
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: Theme.Space.small) {
            Group {
                Button("示范") { player.demoOn.toggle() }
                    .buttonStyle(Pill(isOn: player.demoOn))
                    .accessibilityAddTraits(player.demoOn ? .isSelected : [])
                    .disabled(!player.canDemo)
                Button("节拍") { player.clickOn.toggle() }
                    .buttonStyle(Pill(isOn: player.clickOn))
                    .accessibilityAddTraits(player.clickOn ? .isSelected : [])
            }
            .disabled(player.isRunning)
            TimelineView(.animation(paused: !player.isRunning)) { _ in
                beatDots(player.beatInBar)
            }
            .padding(.leading, Theme.Space.small)
            Spacer(minLength: 0)
            if !isStopped {
                Button {
                    player.stop()
                } label: {
                    Label("停止", systemImage: "stop.fill")
                        .frame(width: 44, height: 44)
                        .overlay { Circle().strokeBorder(Theme.outline, lineWidth: 1) }
                        .contentShape(Circle())
                }
                .labelStyle(.iconOnly)
                .font(.system(size: 15))
                .foregroundStyle(Theme.ink)
            }
            playButton
        }
        .padding(.horizontal, Theme.Space.gutter)
        .padding(.vertical, Theme.Space.small)
        .background(Theme.raised)
        .overlay(alignment: .top) { Theme.rule.frame(height: 1) }
        // One fixed-height row: larger text would push the controls off the screen.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .animation(.easeInOut(duration: 0.2), value: isStopped)
    }

    private var playButton: some View {
        // The frame and disc sit inside the label, so the whole disc is the target and dims when pressed.
        Button {
            player.playOrPause()
        } label: {
            Label(playTitle, systemImage: player.isRunning ? "pause.fill" : "play.fill")
                .frame(width: 56, height: 56)
                .background(Theme.accent, in: Circle())
                .contentShape(Circle())
        }
        .labelStyle(.iconOnly)
        .font(.system(size: 22))
        .foregroundStyle(Theme.onAccent)
        .shadow(color: colorScheme == .dark ? .clear : Theme.accent.opacity(0.28), radius: 9, y: 6)
        .contentTransition(.opacity)
        .animation(.easeInOut(duration: 0.2), value: player.isRunning)
        .disabled(!player.isRunning && !player.canPlay)
        .opacity(player.isRunning || player.canPlay ? 1 : 0.4)
    }

    /// Before playing, the dots show the piece's meter, none lit.
    private var beatsPerBar: Int {
        guard case .meter(let beats, _) = player.score.measures.first?.time else { return 0 }
        return beats
    }

    private var isStopped: Bool {
        if case .stopped = player.transport { true } else { false }
    }

    private var playTitle: LocalizedStringKey { player.isRunning ? "暂停" : "开始" }

    private func beatDots(_ beat: (index: Int, count: Int)?) -> some View {
        let count = beat?.count ?? beatsPerBar
        return HStack(spacing: count > 4 ? 6 : 8) {
            ForEach(0..<count, id: \.self) { index in
                if index == beat?.index {
                    Circle().fill(Theme.accent).frame(width: 11, height: 11)
                } else {
                    Circle().strokeBorder(Theme.muted, lineWidth: 1.5).frame(width: 11, height: 11)
                }
            }
        }
        .frame(minHeight: 11)
    }
}

/// A capsule button in the theme's colours: accent-filled when on, outlined in ink when off.
private struct Pill: ButtonStyle {
    let isOn: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline)
            .padding(.horizontal, Theme.Space.large)
            .frame(minHeight: 36)
            .foregroundStyle(isOn ? Theme.onAccent : Theme.ink)
            .background(isOn ? Theme.accent : Color.clear, in: Capsule())
            .overlay { Capsule().strokeBorder(isOn ? Color.clear : Theme.outline, lineWidth: 1) }
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .animation(.easeInOut(duration: 0.2), value: isOn)
            // The capsule is 36 pt; the tap area reaches 44.
            .padding(.vertical, 4)
            .contentShape(Rectangle())
    }
}
