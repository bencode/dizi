import ScoreKit
import SwiftUI

/// The controls floating over the bottom of the score, on the glass layer: a capsule with the 示范 and 节拍
/// switches and the beat, then stop (while playing or paused) and start/pause.
struct TransportBar: View {
    @Bindable var player: Player
    @Namespace private var glass

    var body: some View {
        GlassEffectContainer(spacing: Theme.Space.medium) {
            HStack(spacing: Theme.Space.medium) {
                HStack(spacing: Theme.Space.tiny) {
                    Group {
                        Button("示范") { player.demoOn.toggle() }
                            .buttonStyle(Switch(isOn: player.demoOn))
                            .accessibilityAddTraits(player.demoOn ? .isSelected : [])
                            .disabled(!player.canDemo)
                        Button("节拍") { player.clickOn.toggle() }
                            .buttonStyle(Switch(isOn: player.clickOn))
                            .accessibilityAddTraits(player.clickOn ? .isSelected : [])
                    }
                    .disabled(player.isRunning)
                    TimelineView(.animation(paused: !player.isRunning)) { _ in
                        beatDots(player.beatInBar)
                    }
                    .padding(.horizontal, Theme.Space.small)
                }
                // 10 inside a 56 capsule keeps the 36 switch capsules concentric (28 − 10 = 18).
                .padding(.horizontal, 10)
                .frame(minHeight: 56)
                .glassEffect(.regular, in: .capsule)
                Spacer(minLength: 0)
                if !isStopped {
                    Button {
                        player.stop()
                    } label: {
                        Label("停止", systemImage: "stop.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .glassEffectID("stop", in: glass)
                }
                playButton.glassEffectID("play", in: glass)
            }
        }
        .labelStyle(.iconOnly)
        .padding(.horizontal, Theme.Space.large)
        .padding(.bottom, Theme.Space.small)
        // One row: larger text would push the controls off the screen.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .animation(.default, value: isStopped)
    }

    /// The primary action: the only tinted glass in the app.
    private var playButton: some View {
        Button {
            player.playOrPause()
        } label: {
            Label(playTitle, systemImage: player.isRunning ? "pause.fill" : "play.fill")
                .font(.system(size: 22))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 40, height: 40)
                .contentTransition(.opacity)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.circle)
        .tint(Theme.accent)
        .animation(.easeInOut(duration: 0.2), value: player.isRunning)
        .disabled(!player.isRunning && !player.canPlay)
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

/// A switch (示范, 节拍, 选段): an accent capsule when on, plain ink text when off.
struct Switch: ButtonStyle {
    let isOn: Bool
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 14)
            .frame(minHeight: 36)
            .foregroundStyle(isOn ? Theme.onAccent : Theme.ink)
            .background(isOn ? Theme.accent : Color.clear, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .animation(.easeInOut(duration: 0.2), value: isOn)
            // The capsule is 36 pt; the tap area reaches 44.
            .padding(.vertical, 4)
            .contentShape(Rectangle())
    }
}
