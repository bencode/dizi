import AVFoundation
import OSLog
import ScoreKit

private let logger = Logger(subsystem: "io.upivot.dizi", category: "audio")

/// The audio edge of 走谱: plays a run's clicks and, optionally, its demo melody, both sample-accurately from
/// one start time, and reports the time since the run began, which is the clock the cursor follows.
@MainActor
final class RunAudio {
    static let sampleRate = 44_100.0

    private let engine = AVAudioEngine()
    private let clickNode = AVAudioPlayerNode()
    private let melodyNode = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private let accentBuffer: AVAudioPCMBuffer
    private let beatBuffer: AVAudioPCMBuffer
    /// A click's length of silence: the music's clicks while 节拍 is off, still keeping the run's clock.
    private let silentBuffer: AVAudioPCMBuffer
    /// Host time of the run's time 0, while a run is scheduled.
    private var startHostTime: UInt64?

    init() throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1),
            let accent = buffer(clickSamples(frequency: 1_760, sampleRate: format.sampleRate), format: format),
            let beat = buffer(clickSamples(frequency: 1_175, sampleRate: format.sampleRate), format: format),
            let silent = buffer([Float](repeating: 0, count: Int(beat.frameLength)), format: format)
        else { throw RunAudioError.noAudioFormat }
        self.format = format
        accentBuffer = accent
        beatBuffer = beat
        silentBuffer = silent
        for node in [clickNode, melodyNode] {
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
        }
    }

    /// Starts a run; time 0 is the first click. The count-in always sounds; the music's clicks sound when
    /// `musicClicksAudible`, and are silent otherwise but still drive the clock. The melody, rendered at
    /// `sampleRate` from time 0, starts on the same sample.
    func start(_ clicks: [Click], musicClicksAudible: Bool, melody: [Float]?) throws {
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try AVAudioSession.sharedInstance().setActive(true)
        if !engine.isRunning {
            try engine.start()
        }
        clickNode.stop()
        melodyNode.stop()
        for click in clicks {
            let when = AVAudioTime(
                sampleTime: AVAudioFramePosition(click.time * format.sampleRate), atRate: format.sampleRate)
            let sound =
                click.countIn || musicClicksAudible ? (click.accent ? accentBuffer : beatBuffer) : silentBuffer
            clickNode.scheduleBuffer(sound, at: when)
        }
        if let melody, let melodyBuffer = buffer(melody, format: format) {
            melodyNode.scheduleBuffer(melodyBuffer, at: AVAudioTime(sampleTime: 0, atRate: format.sampleRate))
        }
        // Both nodes start on one host time a moment ahead, so they cannot drift apart.
        let startTime = AVAudioTime(hostTime: mach_absolute_time() + AVAudioTime.hostTime(forSeconds: 0.05))
        clickNode.play(at: startTime)
        melodyNode.play(at: startTime)
        startHostTime = startTime.hostTime
    }

    /// Ends the run and gives the audio back: the hardware (pause() would keep the IO thread running) and the
    /// session, so music that 走谱 interrupted may resume.
    func stop() {
        clickNode.stop()
        melodyNode.stop()
        engine.stop()
        startHostTime = nil
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            logger.error("Cannot release the audio session: \(error, privacy: .public)")
        }
    }

    /// Seconds since time 0 of the current run, from the render clock; when the engine has stopped under the run
    /// (an interruption, a route change), from the host clock, so a pause still lands where the run was.
    /// Nil when nothing is scheduled.
    var time: Double? {
        guard let startHostTime else { return nil }
        let now = mach_absolute_time()
        guard let nodeTime = clickNode.lastRenderTime, nodeTime.isHostTimeValid,
            let playerTime = clickNode.playerTime(forNodeTime: nodeTime)
        else { return max(0, seconds(from: startHostTime, to: now)) }
        // The render time moves once per audio buffer; add the time since that render so every frame advances.
        return max(0, Double(playerTime.sampleTime) / playerTime.sampleRate + seconds(from: nodeTime.hostTime, to: now))
    }

    /// Yields each time the system stops this audio: an interruption begins (Siri, an alarm, a call), or the
    /// engine's configuration changes (headphones unplugged, a Bluetooth route). Ends when its consumer does.
    func interruptions() -> AsyncStream<Void> {
        let (stream, continuation) = AsyncStream<Void>.makeStream()
        let center = NotificationCenter.default
        let session = Task {
            for await note in center.notifications(named: AVAudioSession.interruptionNotification)
            where interruptionBegan(note) {
                continuation.yield()
            }
        }
        let route = Task {
            for await _ in center.notifications(named: .AVAudioEngineConfigurationChange, object: engine) {
                continuation.yield()
            }
        }
        continuation.onTermination = { _ in
            session.cancel()
            route.cancel()
        }
        return stream
    }
}

private func seconds(from start: UInt64, to end: UInt64) -> Double {
    AVAudioTime.seconds(forHostTime: end) - AVAudioTime.seconds(forHostTime: start)
}

private func interruptionBegan(_ note: Notification) -> Bool {
    (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
        == .began
}

enum RunAudioError: Error {
    case noAudioFormat
}

/// A short decaying tone: the sound of one click.
private func clickSamples(frequency: Double, sampleRate: Double) -> [Float] {
    let count = Int(sampleRate * 0.03)
    return (0..<count).map { index in
        let time = Double(index) / sampleRate
        return Float(sin(2 * .pi * frequency * time) * exp(-time * 150) * 0.8)
    }
}

private func buffer(_ samples: [Float], format: AVAudioFormat) -> AVAudioPCMBuffer? {
    guard !samples.isEmpty,
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
        let channel = buffer.floatChannelData?[0]
    else { return nil }
    buffer.frameLength = AVAudioFrameCount(samples.count)
    for (index, sample) in samples.enumerated() {
        channel[index] = sample
    }
    return buffer
}
