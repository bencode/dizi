import AVFoundation
import ScoreKit
import SwiftUI

/// 调音器: the note the player blows in jianpu on their flute, how far off it is in cents, and how long this breath
/// has lasted. For tuning the flute (pull the joint until the 筒音 reads 准) and for checking single notes.
struct TunerView: View {
    @AppStorage("tuner.flute") private var flute: Flute = .keyD
    @AppStorage("tuner.tube") private var tube = 5
    @State private var access: Access = .unknown
    @State private var heard: Heard?
    /// When the current breath began, and the longest on this visit, in seconds.
    @State private var breathStart: Date?
    @State private var lastSound: Date?
    @State private var longest: TimeInterval = 0
    @State private var held: TimeInterval = 0

    private enum Access { case unknown, granted, denied }

    /// The latest reading: the detected frequency and the note it reads as.
    private struct Heard {
        let frequency: Double
        let note: TunedNote
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.ground)
            .navigationTitle("调音器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .tabBar)
            // Hands are on the flute.
            .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
            .task { await listen() }
    }

    @ViewBuilder private var content: some View {
        switch access {
        case .unknown:
            Color.clear
        case .denied:
            ContentUnavailableView {
                Label("需要麦克风", systemImage: "mic.slash")
            } description: {
                Text("调音器要听你吹的音。请在设置里允许鱼米竹笛使用麦克风。")
            } actions: {
                Button("去设置") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(Switch(isOn: true))
            }
            .foregroundStyle(Theme.muted)
        case .granted:
            tuner
        }
    }

    private var tuner: some View {
        VStack(spacing: Theme.Space.wider) {
            pickers
            Spacer(minLength: 0)
            JianpuNote(note: heard?.note)
            Text(
                verbatim: heard.map {
                    "\($0.note.concert) · \($0.frequency.formatted(.number.precision(.fractionLength(1)))) Hz"
                } ?? " "
            )
            .font(.subheadline)
            .monospacedDigit()
            .foregroundStyle(Theme.muted)
            Needle(cents: heard?.note.cents)
            verdict
            Spacer(minLength: 0)
            Text("这口气 \(seconds(held)) 秒 · 最长 \(seconds(longest)) 秒")
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(Theme.muted)
        }
        .padding(Theme.Space.gutter)
    }

    private var pickers: some View {
        HStack {
            Picker("笛子", selection: $flute) {
                ForEach(Flute.allCases, id: \.self) { Text(fluteName($0)).tag($0) }
            }
            Spacer()
            Picker("指法", selection: $tube) {
                Text("筒音作5").tag(5)
                Text("筒音作2").tag(2)
            }
        }
        .pickerStyle(.menu)
        .tint(Theme.ink)
    }

    /// 准 within ±5 cents; otherwise how far and which way.
    @ViewBuilder private var verdict: some View {
        if let cents = heard?.note.cents {
            let rounded = Int(cents.rounded())
            let signed = rounded > 0 ? "+\(rounded)" : "\(rounded)"
            HStack(spacing: 0) {
                Text("\(signed) 音分 · ")
                if abs(cents) <= 5 {
                    Text("准").foregroundStyle(Theme.ink)
                } else {
                    Text(cents > 0 ? "偏高" : "偏低").foregroundStyle(Theme.accent)
                }
            }
            .font(.title3.weight(.medium))
            .monospacedDigit()
            .foregroundStyle(Theme.muted)
        } else {
            Text(verbatim: " ").font(.title3)
        }
    }

    /// Asks for the microphone if need be, then reads it until the page goes away.
    private func listen() async {
        switch Microphone.permission {
        case .granted: access = .granted
        case .denied: access = .denied
        case .undetermined: access = await Microphone.requestPermission() ? .granted : .denied
        @unknown default: access = .denied
        }
        guard access == .granted else { return }
        let microphone = Microphone()
        let listening: (windows: AsyncStream<[Float]>, sampleRate: Double)
        do {
            listening = try microphone.start()
        } catch {
            access = .denied
            return
        }
        var recent: [Double] = []
        for await window in listening.windows {
            let rate = listening.sampleRate
            let frequency = await Task.detached(priority: .userInitiated) {
                detectedFrequency(window, sampleRate: rate)
            }.value
            recent = Array((recent + [frequency].compactMap { $0 }).suffix(3))
            hear(frequency.flatMap { _ in median(recent) }, at: .now)
        }
        microphone.stop()
    }

    /// Updates the reading and the breath: a breath is sound with no gap longer than 0.3 s.
    private func hear(_ frequency: Double?, at now: Date) {
        if let frequency {
            heard = Heard(frequency: frequency, note: tunedNote(frequency: frequency, flute: flute, tube: tube))
            if breathStart == nil || now.timeIntervalSince(lastSound ?? now) > 0.3 {
                breathStart = now
            }
            lastSound = now
            held = now.timeIntervalSince(breathStart ?? now)
            longest = max(longest, held)
        } else if now.timeIntervalSince(lastSound ?? .distantPast) > 0.3 {
            withAnimation(.easeOut(duration: 0.3)) { heard = nil }
            breathStart = nil
        }
    }
}

private func seconds(_ interval: TimeInterval) -> String {
    interval.formatted(.number.precision(.fractionLength(1)))
}

private func median(_ values: [Double]) -> Double? {
    values.isEmpty ? nil : values.sorted()[values.count / 2]
}

private func fluteName(_ flute: Flute) -> LocalizedStringKey {
    switch flute {
    case .bigG: "大G调笛"
    case .bigA: "大A调笛"
    case .bigBFlat: "大♭B调笛"
    case .keyC: "C调笛"
    case .keyD: "D调笛"
    case .keyE: "E调笛"
    case .keyF: "F调笛"
    case .keyG: "G调笛"
    }
}

/// The sounding note as a large jianpu digit, with its accidental and octave dots; a dash in silence.
private struct JianpuNote: View {
    let note: TunedNote?

    var body: some View {
        VStack(spacing: 6) {
            dots(note.map { max($0.octave, 0) } ?? 0)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                if let accidental = note?.accidental {
                    Text(verbatim: accidental == .sharp ? "♯" : "♭").font(Theme.serif(40))
                }
                Text(verbatim: note.map { "\($0.degree)" } ?? "—").font(Theme.serif(96))
            }
            dots(note.map { max(-$0.octave, 0) } ?? 0)
        }
        .foregroundStyle(note == nil ? Theme.muted : Theme.ink)
        .frame(height: 170)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(note.map { Text(verbatim: "\($0.concert)") } ?? Text("没有声音"))
    }

    private func dots(_ count: Int) -> some View {
        VStack(spacing: 5) {
            ForEach(0..<count, id: \.self) { _ in Circle().frame(width: 9, height: 9) }
        }
        .frame(height: 23)
    }
}

/// −50…+50 cents as a dot on a line, the in-tune centre marked in accent.
private struct Needle: View {
    let cents: Double?

    var body: some View {
        VStack(spacing: Theme.Space.small) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let offset = CGFloat(min(max(cents ?? 0, -50), 50) / 50) * width / 2
                ZStack {
                    Capsule().fill(Theme.rule).frame(height: 2)
                    Capsule().fill(Theme.accent).frame(width: 2, height: 22)
                    Circle()
                        .fill(cents.map { abs($0) <= 5 ? Theme.ink : Theme.accent } ?? Theme.muted)
                        .frame(width: 18, height: 18)
                        .offset(x: offset)
                        .animation(.easeOut(duration: 0.15), value: offset)
                }
                .frame(width: width, height: 24)
            }
            .frame(height: 24)
            HStack {
                Text("偏低")
                Spacer()
                Text("偏高")
            }
            .font(.footnote)
            .foregroundStyle(Theme.muted)
        }
        .accessibilityHidden(true)
    }
}
