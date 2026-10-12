import AVFoundation
import OSLog

private let logger = Logger(subsystem: "io.upivot.dizi", category: "microphone")

/// The microphone edge: windows of what the player blows, for pitch detection. Nothing is recorded or kept; each
/// window is handed on and dropped.
@MainActor
final class Microphone {
    /// Samples per window: about 90 ms at 44.1 kHz, two periods of the lowest dizi note with room to spare.
    static let windowLength = 4096

    private let engine = AVAudioEngine()

    static var permission: AVAudioApplication.recordPermission { AVAudioApplication.shared.recordPermission }

    static func requestPermission() async -> Bool { await AVAudioApplication.requestRecordPermission() }

    /// Starts listening: the latest `windowLength` samples each time the hardware delivers more, and their rate.
    /// Measurement mode, so no voice processing bends the pitch. Call `stop()` when done.
    func start() throws -> (windows: AsyncStream<[Float]>, sampleRate: Double) {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement)
        try session.setActive(true)
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        let (windows, continuation) = AsyncStream<[Float]>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let recent = Recent(length: Self.windowLength)
        input.installTap(onBus: 0, bufferSize: 2048, format: format) { @Sendable buffer, _ in
            guard let channel = buffer.floatChannelData?[0] else { return }
            if let window = recent.appending(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength))) {
                continuation.yield(window)
            }
        }
        try engine.start()
        return (windows, format.sampleRate)
    }

    /// Stops listening and gives the audio back, so music the tuner interrupted may resume.
    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            logger.error("Cannot release the audio session: \(error, privacy: .public)")
        }
    }
}

/// The latest samples, kept on the audio thread that calls the tap; nothing else touches them.
private final class Recent: @unchecked Sendable {
    private let length: Int
    private var samples: [Float] = []

    init(length: Int) {
        self.length = length
    }

    /// Adds samples; returns the latest `length` once there are that many.
    func appending(_ more: UnsafeBufferPointer<Float>) -> [Float]? {
        samples.append(contentsOf: more)
        if samples.count > length {
            samples.removeFirst(samples.count - length)
        }
        return samples.count == length ? samples : nil
    }
}
