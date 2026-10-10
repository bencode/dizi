import Foundation
import OSLog
import ScoreKit

private let logger = Logger(subsystem: "io.upivot.dizi", category: "player")

/// The single source of truth for 走谱 on one piece: transport state, tempo, and the click switch.
/// State changes go through `Transport.next`; this class only adds the effects (audio, saving the tempo).
@MainActor
@Observable
final class Player {
    let score: Score
    let timeline: Timeline
    private(set) var transport: Transport = .stopped(start: 0)
    private var run: Run?
    var bpm: Int {
        didSet { UserDefaults.standard.set(bpm, forKey: tempoKey) }
    }
    var clickOn = true
    /// 示范: the app plays the melody too.
    var demoOn = false

    private let beat: Int
    private let tempoKey: String
    private let audio: RunAudio?
    private let voices: [Voice]
    private var finishTask: Task<Void, Never>?
    /// Pauses the run when the system stops its audio; lives as long as the run.
    private var interruptionTask: Task<Void, Never>?

    init(pieceID: String, score: Score) {
        self.score = score
        timeline = Timeline(score: score)
        let written = score.startingTempo
        beat = written?.beat ?? 480
        tempoKey = "tempo.\(pieceID)"
        let saved = UserDefaults.standard.integer(forKey: tempoKey)
        bpm = saved > 0 ? saved : written.flatMap(defaultBPM) ?? 72
        audio = {
            do {
                return try RunAudio()
            } catch {
                logger.error("Audio unavailable: \(error, privacy: .public)")
                return nil
            }
        }()
        voices = {
            do {
                return try bundledVoices()
            } catch {
                logger.error("Demo voice unavailable: \(error, privacy: .public)")
                return []
            }
        }()
    }

    static let tempoRange = 30...240

    /// False for a score without notes, or when the audio could not start up.
    var canPlay: Bool { !timeline.entries.isEmpty && audio != nil }

    /// False when the demo voice could not be loaded.
    var canDemo: Bool { !voices.isEmpty }

    var isRunning: Bool {
        if case .running = transport { return true }
        return false
    }

    /// Where the run is now, read from the audio clock.
    var position: Run.Position? {
        guard let run, let time = audio?.time else { return nil }
        return run.position(at: time, in: timeline)
    }

    var beatInBar: (index: Int, count: Int)? {
        guard let run, let time = audio?.time else { return nil }
        return run.beat(at: time, in: timeline)
    }

    /// Where the playhead stands: the sounding entry and how much of it has passed while running,
    /// the paused entry while paused, nothing while stopped.
    var sweep: (entry: Int, progress: Double)? {
        switch transport {
        case .running:
            guard case .entry(let entry, let progress) = position else { return nil }
            return (entry, progress)
        case .paused(let entry, _):
            return (entry, 0)
        case .stopped:
            return nil
        }
    }

    func playOrPause() {
        if isRunning {
            pause()
        } else {
            play()
        }
    }

    func select(noteID: String) {
        guard let entry = timeline.firstEntry(of: noteID) else { return }
        transport = transport.next(.select(entry))
    }

    func stop() {
        halt()
        transport = transport.next(.stop)
    }

    /// Pauses a running run; does nothing otherwise (e.g. when the app leaves the screen).
    func pause() {
        guard isRunning else { return }
        let entry = sweep?.entry ?? run?.from ?? 0
        halt()
        transport = transport.next(.pause(entry: entry))
    }

    private func play() {
        guard canPlay, let audio else { return }
        transport = transport.next(.play)
        guard case .running(let from, _) = transport else { return }
        let run = Run(from: from, tempo: Tempo(bpm: Double(bpm), beat: beat))
        do {
            let melody =
                demoOn && canDemo
                ? melodySamples(run.melody(timeline, score: score), voices: voices, sampleRate: RunAudio.sampleRate)
                : nil
            try audio.start(run.clicks(timeline), clicksAudible: clickOn, melody: melody)
        } catch {
            logger.error("Cannot start the clicks: \(error, privacy: .public)")
            transport = transport.next(.stop)
            return
        }
        self.run = run
        finishTask = Task { [weak self, length = run.length(timeline)] in
            do {
                try await Task.sleep(for: .seconds(length))
            } catch is CancellationError {
                return  // stopped or paused before the end
            } catch {
                logger.error("Finish timer failed: \(error, privacy: .public)")
                return
            }
            self?.finish()
        }
        interruptionTask = Task { [weak self, interruptions = audio.interruptions()] in
            for await _ in interruptions {
                self?.pause()
                return
            }
        }
    }

    private func finish() {
        halt()
        transport = transport.next(.finish)
    }

    private func halt() {
        finishTask?.cancel()
        finishTask = nil
        interruptionTask?.cancel()
        interruptionTask = nil
        audio?.stop()
        run = nil
    }
}

/// The written tempo to start from; the slower end of a range like ♩=58~80.
private func defaultBPM(_ tempo: TempoMark) -> Int? {
    switch tempo.bpm {
    case .exact(let bpm): bpm
    case .range(let low, _): low
    case nil: nil
    }
}
