import AVFoundation
import ScoreKit

/// The audio edge of 走谱: plays a run's clicks sample-accurately and reports the time since the run began,
/// which is the clock the cursor follows.
@MainActor
final class ClickTrack {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format: AVAudioFormat
    private let accentBuffer: AVAudioPCMBuffer
    private let beatBuffer: AVAudioPCMBuffer

    init() throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1),
            let accent = buffer(clickSamples(frequency: 1_760, sampleRate: format.sampleRate), format: format),
            let beat = buffer(clickSamples(frequency: 1_175, sampleRate: format.sampleRate), format: format)
        else { throw ClickTrackError.noAudioFormat }
        self.format = format
        accentBuffer = accent
        beatBuffer = beat
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
    }

    /// Starts a run; time 0 is the first click. Silent clicks still drive the clock.
    func start(_ clicks: [Click], audible: Bool) throws {
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
        try AVAudioSession.sharedInstance().setActive(true)
        if !engine.isRunning {
            try engine.start()
        }
        player.stop()
        player.volume = audible ? 1 : 0
        for click in clicks {
            let when = AVAudioTime(
                sampleTime: AVAudioFramePosition(click.time * format.sampleRate), atRate: format.sampleRate)
            player.scheduleBuffer(click.accent ? accentBuffer : beatBuffer, at: when)
        }
        player.play()
    }

    func stop() {
        player.stop()
        engine.pause()
    }

    /// Seconds since time 0 of the current run; nil when nothing is playing yet.
    var time: Double? {
        guard let nodeTime = player.lastRenderTime, nodeTime.isHostTimeValid,
            let playerTime = player.playerTime(forNodeTime: nodeTime)
        else { return nil }
        // The render time moves once per audio buffer; add the time since that render so every frame advances.
        let sinceRender =
            AVAudioTime.seconds(forHostTime: mach_absolute_time()) - AVAudioTime.seconds(forHostTime: nodeTime.hostTime)
        return max(0, Double(playerTime.sampleTime) / playerTime.sampleRate + sinceRender)
    }
}

enum ClickTrackError: Error {
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
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
        let channel = buffer.floatChannelData?[0]
    else { return nil }
    buffer.frameLength = AVAudioFrameCount(samples.count)
    for (index, sample) in samples.enumerated() {
        channel[index] = sample
    }
    return buffer
}
