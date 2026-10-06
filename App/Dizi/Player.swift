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
    private(set) var run: Run?
    var bpm: Int {
        didSet { UserDefaults.standard.set(bpm, forKey: tempoKey) }
    }
    var clickOn = true

    private let beat: Int
    private let tempoKey: String
    private let clickTrack: ClickTrack?
    private var finishTask: Task<Void, Never>?

    init(pieceID: String, score: Score) {
        self.score = score
        timeline = Timeline(score: score)
        let written = score.marks.lazy.compactMap(startingTempo).first
        beat = written?.beat ?? 480
        tempoKey = "tempo.\(pieceID)"
        let saved = UserDefaults.standard.integer(forKey: tempoKey)
        bpm = saved > 0 ? saved : written?.bpm ?? 72
        clickTrack = {
            do {
                return try ClickTrack()
            } catch {
                logger.error("Audio unavailable: \(error, privacy: .public)")
                return nil
            }
        }()
    }

    static let tempoRange = 30...240

    var isRunning: Bool {
        if case .running = transport { return true }
        return false
    }

    /// Where the run is now, read from the audio clock.
    var position: Run.Position? {
        guard let run, let time = clickTrack?.time else { return nil }
        return run.position(at: time, in: timeline)
    }

    var beatInBar: (index: Int, count: Int)? {
        guard let run, let time = clickTrack?.time else { return nil }
        return run.beat(at: time, in: timeline)
    }

    /// The entry to highlight: the sounding one while running, the chosen one otherwise.
    var highlighted: Int? {
        switch transport {
        case .running:
            guard case .entry(let entry) = position else { return nil }
            return entry
        case .paused(let entry, _), .stopped(let entry):
            return entry
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

    private func play() {
        transport = transport.next(.play)
        guard case .running(let from, _) = transport, let clickTrack else { return }
        let run = Run(from: from, tempo: Tempo(bpm: Double(bpm), beat: beat))
        do {
            try clickTrack.start(run.clicks(timeline), audible: clickOn)
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
    }

    private func pause() {
        let entry = highlighted ?? run?.from ?? 0
        halt()
        transport = transport.next(.pause(entry: entry))
    }

    private func finish() {
        halt()
        transport = transport.next(.finish)
    }

    private func halt() {
        finishTask?.cancel()
        finishTask = nil
        clickTrack?.stop()
        run = nil
    }
}

private func startingTempo(_ mark: Mark) -> (beat: Int, bpm: Int)? {
    guard case .tempo(let tempo) = mark, tempo.tick == 0 else { return nil }
    return switch tempo.bpm {
    case .exact(let bpm): (tempo.beat, bpm)
    case .range(let low, _): (tempo.beat, low)
    case nil: nil
    }
}
