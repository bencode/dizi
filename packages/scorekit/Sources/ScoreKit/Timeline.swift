import Foundation

/// The solo part in playing order (repeats unrolled), on one musical clock in ticks.
public struct Timeline: Sendable {
    /// One note or rest as it is played. A repeated passage yields its ids again.
    public struct Entry: Sendable, Equatable {
        public let id: String
        /// Ticks from the start of the performance.
        public let start: Int
        public let duration: Int
        /// The measure in `Score.measures`.
        public let measure: Int
    }

    /// A played measure: where it falls in the performance and how its beats are counted.
    public struct Bar: Sendable, Equatable {
        public let measure: Int
        public let start: Int
        public let duration: Int
        public let time: TimeSignature
    }

    public let entries: [Entry]
    public let bars: [Bar]

    public init(score: Score) {
        let part = score.parts.first { $0.role == .solo }
        let durations = score.playOrder.map { score.measures[$0].duration }
        let bars = zip(score.playOrder, offsets(of: durations)).map { index, start in
            Bar(
                measure: index, start: start, duration: score.measures[index].duration, time: score.measures[index].time
            )
        }
        self.bars = bars
        self.entries = bars.flatMap { bar in
            (part?.measures[bar.measure].events ?? []).compactMap { event in
                playedEntry(event, in: bar, measureStart: score.measures[bar.measure].start)
            }
        }
    }

    public var end: Int { bars.last.map { $0.start + $0.duration } ?? 0 }

    /// The first entry played for a note id, e.g. the note the player tapped.
    public func firstEntry(of id: String) -> Int? {
        entries.firstIndex { $0.id == id }
    }

    /// The entry sounding at a performance tick; nil before the first and from the end on.
    public func entry(at tick: Int) -> Int? {
        entries.lastIndex { $0.start <= tick }.flatMap { index in
            tick < entries[index].start + entries[index].duration ? index : nil
        }
    }
}

private func playedEntry(_ event: Event, in bar: Timeline.Bar, measureStart: Int) -> Timeline.Entry? {
    switch event {
    case .note(let note):
        Timeline.Entry(
            id: note.id, start: bar.start + note.start - measureStart, duration: note.duration, measure: bar.measure)
    case .rest(let rest):
        Timeline.Entry(
            id: rest.id, start: bar.start + rest.start - measureStart, duration: rest.duration, measure: bar.measure)
    case .unknown:
        nil
    }
}

/// Where each of `lengths` starts when laid end to end from zero.
private func offsets(of lengths: [Int]) -> [Int] {
    lengths.dropLast().reduce(into: [0]) { starts, length in starts.append((starts.last ?? 0) + length) }
}

/// How fast the musical clock runs.
public struct Tempo: Sendable, Equatable {
    public let bpm: Double
    /// The beat's length in ticks: 480 for ♩, 720 for ♩.
    public let beat: Int

    public init(bpm: Double, beat: Int) {
        self.bpm = bpm
        self.beat = beat
    }

    public func seconds(_ ticks: Int) -> Double { Double(ticks) / Double(beat) * 60 / bpm }
    public func ticks(_ seconds: Double) -> Int { Int((seconds * bpm / 60 * Double(beat)).rounded(.down)) }
}

/// One click of the metronome, in seconds from the start of a run.
public struct Click: Sendable, Equatable {
    public let time: Double
    /// The first beat of a bar.
    public let accent: Bool
}

/// One pass of 走谱 from an entry: a bar of count-in, then the score to its end. Time 0 is the first count-in click.
public struct Run: Sendable, Equatable {
    public let from: Int
    public let tempo: Tempo

    public init(from: Int, tempo: Tempo) {
        self.from = from
        self.tempo = tempo
    }

    /// What the run shows at a moment.
    public enum Position: Sendable, Equatable {
        /// `beatsLeft` counts down to 1 before the music starts.
        case countIn(beatsLeft: Int)
        /// The entry sounding, and how much of it has passed (0 up to 1).
        case entry(Int, progress: Double)
        case finished
    }

    /// The count-in's length in ticks: one full bar of the start's time signature, even when the music
    /// starts on a pickup; none in 散板.
    public func countInLength(_ timeline: Timeline) -> Int {
        let bar = timeline.bars.first { $0.measure == timeline.entries[from].measure }
        return bar?.fullLength.map { max(1, $0 / tempo.beat) * tempo.beat } ?? 0
    }

    public func position(at seconds: Double, in timeline: Timeline) -> Position {
        let elapsed = tempo.ticks(seconds) - countInLength(timeline)
        guard elapsed >= 0 else { return .countIn(beatsLeft: (-elapsed - 1) / tempo.beat + 1) }
        let tick = timeline.entries[from].start + elapsed
        guard let index = timeline.entry(at: tick) else { return .finished }
        let entry = timeline.entries[index]
        return .entry(index, progress: Double(tick - entry.start) / Double(entry.duration))
    }

    /// The count-in and every beat from the start entry to the end, accented on each bar's downbeat.
    public func clicks(_ timeline: Timeline) -> [Click] {
        let origin = timeline.entries[from].start
        let lead = countInLength(timeline)
        let countIn = stride(from: 0, to: lead, by: tempo.beat).map { tick in
            Click(time: tempo.seconds(tick), accent: tick == 0)
        }
        let music = timeline.bars.filter { $0.start + $0.duration > origin }.flatMap { bar in
            beats(of: bar).filter { $0.tick >= origin }.map { beat in
                Click(time: tempo.seconds(lead + beat.tick - origin), accent: beat.downbeat)
            }
        }
        return countIn + music
    }

    /// The beat sounding at a moment, counted within its bar from 0; nil during the count-in, in 散板, and after the end.
    public func beat(at seconds: Double, in timeline: Timeline) -> (index: Int, count: Int)? {
        let tick = timeline.entries[from].start + tempo.ticks(seconds) - countInLength(timeline)
        guard tick >= timeline.entries[from].start, tick < timeline.end,
            let bar = timeline.bars.last(where: { $0.start <= tick }), let full = bar.fullLength
        else { return nil }
        return ((tick - downbeat(of: bar, full: full)) / tempo.beat, max(1, full / tempo.beat))
    }

    /// Seconds from time 0 to the end of the score.
    public func length(_ timeline: Timeline) -> Double {
        tempo.seconds(countInLength(timeline) + timeline.end - timeline.entries[from].start)
    }

    /// Where a bar's beats fall. A first bar shorter than a full one is a pickup (弱起): its beats are the last
    /// beats of a bar, so none of them is the downbeat. 散板 bars have no beats.
    private func beats(of bar: Timeline.Bar) -> [(tick: Int, downbeat: Bool)] {
        guard let full = bar.fullLength else { return [] }
        let downbeat = downbeat(of: bar, full: full)
        return stride(from: downbeat, to: bar.start + bar.duration, by: tempo.beat)
            .filter { $0 >= bar.start }
            .map { ($0, $0 == downbeat) }
    }

    private func downbeat(of bar: Timeline.Bar, full: Int) -> Int {
        bar.start == 0 && bar.duration < full ? bar.duration - full : bar.start
    }
}

extension Timeline.Bar {
    /// A full bar's length on the time signature; nil in 散板.
    var fullLength: Int? {
        guard case .meter(let beats, let unit) = time else { return nil }
        return beats * 1920 / unit
    }
}
