import AVFoundation
import OSLog
import ScoreKit

private let logger = Logger(subsystem: "io.upivot.dizi", category: "audio")

/// The audio edge of 走谱: plays a run's clicks and, optionally, its demo melody, sample-accurately on one clock,
/// and reports the time since the run began, which is the clock the cursor follows. Sound is scheduled only a
/// moment ahead, so what has not been scheduled yet can be replaced: a tempo change from a bar line on.
@MainActor
final class RunAudio {
    static let sampleRate = 44_100.0
    /// How far ahead of the clock sound is scheduled; a change takes effect after it at the earliest.
    private static let horizon = 0.5

    /// What a run sounds, in seconds from its own time 0: its clicks (the count-in always sounds; the music's
    /// clicks only when `musicClicksAudible`) and, optionally, its melody rendered at `sampleRate`.
    struct Material {
        let clicks: [Click]
        let musicClicksAudible: Bool
        let melody: [Float]?
    }

    /// Material sounding from `start` (seconds of the run's clock) until the next source's start.
    private struct Source {
        let start: Double
        let material: Material
    }

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
    private var sources: [Source] = []
    /// The frame up to which sound has been scheduled.
    private var scheduledFrame = 0
    private var feeder: Task<Void, Never>?

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

    /// Seconds of the run's clock up to which sound is scheduled: a change can start here at the earliest.
    var scheduledUntil: Double { Double(scheduledFrame) / format.sampleRate }

    /// Starts a run; time 0 is the first click.
    func start(_ material: Material) throws {
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try AVAudioSession.sharedInstance().setActive(true)
        if !engine.isRunning {
            try engine.start()
        }
        clickNode.stop()
        melodyNode.stop()
        sources = [Source(start: 0, material: material)]
        scheduledFrame = 0
        // Both nodes start on one host time a moment ahead, so they cannot drift apart.
        let startTime = AVAudioTime(hostTime: mach_absolute_time() + AVAudioTime.hostTime(forSeconds: 0.05))
        startHostTime = startTime.hostTime
        feed()
        clickNode.play(at: startTime)
        melodyNode.play(at: startTime)
        feeder = Task { [weak self] in
            while true {
                do {
                    try await Task.sleep(for: .milliseconds(100))
                } catch is CancellationError {
                    return
                } catch {
                    logger.error("Audio feeder stopped: \(error, privacy: .public)")
                    return
                }
                self?.feed()
            }
        }
    }

    /// Sounds `material` from `start` (at or after `scheduledUntil`) instead of what was to come; a change that
    /// has not begun is dropped.
    func replace(from start: Double, with material: Material) {
        sources = sources.filter { $0.start < scheduledUntil } + [Source(start: start, material: material)]
    }

    /// Ends the run and gives the audio back: the hardware (pause() would keep the IO thread running) and the
    /// session, so music that 走谱 interrupted may resume.
    func stop() {
        feeder?.cancel()
        feeder = nil
        clickNode.stop()
        melodyNode.stop()
        engine.stop()
        startHostTime = nil
        sources = []
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            logger.error("Cannot release the audio session: \(error, privacy: .public)")
        }
    }

    /// Schedules every source's sound from `scheduledFrame` up to the horizon ahead of the clock, each source
    /// within its own stretch of time, at exact frames on the nodes' shared timeline.
    private func feed() {
        let rate = format.sampleRate
        let target = Int(((time ?? 0) + Self.horizon) * rate)
        guard target > scheduledFrame else { return }
        let starts = sources.map { Int(($0.start * rate).rounded()) }
        for (index, source) in sources.enumerated() {
            let ends = index + 1 < starts.count ? starts[index + 1] : Int.max
            // A source the clock has passed, or one still to come, has no window: lower ≥ upper.
            let (lower, upper) = (max(scheduledFrame, starts[index]), min(target, ends))
            guard lower < upper else { continue }
            schedule(source.material, offset: starts[index], window: lower..<upper, cut: ends)
        }
        scheduledFrame = target
    }

    /// The part of `material` (whose time 0 is frame `offset`) falling in `window`; its melody fades out just
    /// before `cut`, where the next source takes over.
    private func schedule(_ material: Material, offset: Int, window: Range<Int>, cut: Int) {
        let rate = format.sampleRate
        let fade = Int(0.005 * rate)
        for click in material.clicks {
            let frame = offset + Int((click.time * rate).rounded())
            // The next source sounds the bar line's click itself; rounding must not sound it twice.
            guard window.contains(frame), frame < cut - fade else { continue }
            let sound =
                click.countIn || material.musicClicksAudible
                ? (click.accent ? accentBuffer : beatBuffer) : silentBuffer
            clickNode.scheduleBuffer(sound, at: AVAudioTime(sampleTime: AVAudioFramePosition(frame), atRate: rate))
        }
        guard let melody = material.melody else { return }
        let (lower, upper) = (max(window.lowerBound - offset, 0), min(window.upperBound - offset, melody.count))
        guard lower < upper else { return }  // the melody has ended
        let slice = lower..<upper
        let samples = slice.map { index in
            let left = cut - (offset + index)
            return left < fade ? melody[index] * Float(max(left, 0)) / Float(fade) : melody[index]
        }
        guard let part = buffer(samples, format: format) else { return }
        melodyNode.scheduleBuffer(
            part, at: AVAudioTime(sampleTime: AVAudioFramePosition(offset + slice.lowerBound), atRate: rate))
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
