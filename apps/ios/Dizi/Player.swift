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
    private var performance: Performance?
    /// The practice tempo. While running, a change applies from a coming bar line, once the player stops changing it.
    var bpm: Int {
        didSet {
            UserDefaults.standard.set(bpm, forKey: tempoKey)
            if isRunning, bpm != oldValue {
                retimeSoon()
            }
        }
    }
    /// 原速: the written tempo (the slower end of a range), or 72 for a score without one.
    let writtenBPM: Int
    var clickOn = true
    /// 示范: the app plays the melody too.
    var demoOn = false
    /// 选段: the bars being marked, or marked; a marked passage is what 开始 plays.
    private(set) var selection: Selection = .off

    private let beat: Int
    private let tempoKey: String
    private let audio: RunAudio?
    private let voices: [Voice]
    private var finishTask: Task<Void, Never>?
    /// A tempo change waiting for the player to stop changing it.
    private var retimeTask: Task<Void, Never>?
    /// Pauses the run when the system stops its audio; lives as long as the run.
    private var interruptionTask: Task<Void, Never>?

    init(pieceID: String, score: Score) {
        self.score = score
        timeline = Timeline(score: score)
        let written = score.startingTempo
        beat = written?.beat ?? 480
        tempoKey = "tempo.\(pieceID)"
        let saved = UserDefaults.standard.integer(forKey: tempoKey)
        writtenBPM = written.flatMap(defaultBPM) ?? 72
        bpm = saved > 0 ? saved : writtenBPM
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
        guard let performance, let time = audio?.time else { return nil }
        return performance.position(at: time, in: timeline)
    }

    var beatInBar: (index: Int, count: Int)? {
        guard let performance, let time = audio?.time else { return nil }
        return performance.beat(at: time, in: timeline)
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

    /// The marked passage, if any.
    var passage: Passage? {
        if case .passage(let passage) = selection { passage } else { nil }
    }

    /// Turns 选段 on (waiting for the first bar) or off (clearing the passage); not while playing.
    func toggleSelection() {
        guard !isRunning else { return }
        selection = selection == .off ? .picking : .off
    }

    /// A tap on the score: with 选段 off it picks the note 走谱 starts from; with 选段 on it marks bars, the
    /// first tap the first bar, the next the last, and a tap after that starts a new passage.
    func tap(noteID: String) {
        guard !isRunning, let entry = timeline.firstEntry(of: noteID) else { return }
        let bar = timeline.entries[entry].measure
        switch selection {
        case .off:
            transport = transport.next(.select(entry))
        case .picking, .passage:
            selection = .first(bar)
        case .first(let first):
            guard let marked = ScoreKit.passage(first, bar, in: timeline) else { return }
            selection = .passage(marked)
            transport = transport.next(.select(marked.from))
        }
    }

    func stop() {
        halt()
        transport = transport.next(.stop)
    }

    /// Pauses a running run; does nothing otherwise (e.g. when the app leaves the screen).
    func pause() {
        guard isRunning else { return }
        let entry = sweep?.entry ?? performance?.segments[0].run.from ?? 0
        halt()
        transport = transport.next(.pause(entry: entry))
    }

    private func play() {
        guard canPlay, let audio else { return }
        transport = transport.next(.play)
        guard case .running(let from, _) = transport else { return }
        let run = Run(
            from: from, until: passage?.until, countInBars: CountIn.chosen.rawValue,
            tempo: Tempo(bpm: Double(bpm), beat: beat))
        do {
            try audio.start(material(of: run))
        } catch {
            logger.error("Cannot start the clicks: \(error, privacy: .public)")
            transport = transport.next(.stop)
            return
        }
        let performance = Performance(run)
        self.performance = performance
        finishWhen(performance)
        interruptionTask = Task { [weak self, interruptions = audio.interruptions()] in
            for await _ in interruptions {
                self?.pause()
                return
            }
        }
    }

    /// What a run sounds: its clicks and, with 示范 on, its melody.
    private func material(of run: Run) -> RunAudio.Material {
        let melody =
            demoOn && canDemo
            ? melodySamples(run.melody(timeline, score: score), voices: voices, sampleRate: RunAudio.sampleRate)
            : nil
        return RunAudio.Material(clicks: run.clicks(timeline), musicClicksAudible: clickOn, melody: melody)
    }

    /// Applies the tempo 0.3 s after the last change, so holding + or swiping the dial changes it once.
    private func retimeSoon() {
        retimeTask?.cancel()
        retimeTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .seconds(0.3))
            } catch is CancellationError {
                return
            } catch {
                logger.error("Tempo change timer failed: \(error, privacy: .public)")
                return
            }
            self?.retime()
        }
    }

    /// The running performance at the current tempo from the first bar line not yet scheduled; with none left
    /// before the end, the tempo waits for the next 开始.
    private func retime() {
        guard isRunning, let audio, let performance,
            let retimed = performance.retimed(
                Tempo(bpm: Double(bpm), beat: beat), from: audio.scheduledUntil, in: timeline),
            let change = retimed.segments.last
        else { return }
        audio.replace(from: change.start, with: material(of: change.run))
        self.performance = retimed
        finishWhen(retimed)
    }

    /// Finishes the run when the performance ends, counted from now on the audio clock.
    private func finishWhen(_ performance: Performance) {
        finishTask?.cancel()
        finishTask = Task { [weak self, left = performance.length(timeline) - (audio?.time ?? 0)] in
            do {
                try await Task.sleep(for: .seconds(max(left, 0)))
            } catch is CancellationError {
                return  // stopped or paused before the end
            } catch {
                logger.error("Finish timer failed: \(error, privacy: .public)")
                return
            }
            self?.finish()
        }
    }

    private func finish() {
        halt()
        transport = transport.next(.finish)
    }

    private func halt() {
        finishTask?.cancel()
        finishTask = nil
        retimeTask?.cancel()
        retimeTask = nil
        interruptionTask?.cancel()
        interruptionTask = nil
        audio?.stop()
        performance = nil
    }
}

/// 选段's state: off, waiting for the first bar, waiting for the last (the first marked), or a passage.
enum Selection: Equatable {
    case off, picking
    case first(Int)
    case passage(Passage)
}

/// The written tempo to start from; the slower end of a range like ♩=58~80.
private func defaultBPM(_ tempo: TempoMark) -> Int? {
    switch tempo.bpm {
    case .exact(let bpm): bpm
    case .range(let low, _): low
    case nil: nil
    }
}
