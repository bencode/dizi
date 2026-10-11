/// 走谱 whose tempo may change while it plays: runs laid end to end, each later one starting on a bar line of the
/// one before, without a count-in. Time 0 is the first run's time 0.
public struct Performance: Sendable, Equatable {
    public struct Segment: Sendable, Equatable {
        /// Seconds from time 0.
        public let start: Double
        public let run: Run
    }

    /// In time order; never empty, and the first starts at 0.
    public let segments: [Segment]

    public init(_ run: Run) {
        segments = [Segment(start: 0, run: run)]
    }

    private init(segments: [Segment]) {
        self.segments = segments
    }

    public func position(at seconds: Double, in timeline: Timeline) -> Run.Position {
        let segment = segment(at: seconds)
        return segment.run.position(at: seconds - segment.start, in: timeline)
    }

    public func beat(at seconds: Double, in timeline: Timeline) -> (index: Int, count: Int)? {
        let segment = segment(at: seconds)
        return segment.run.beat(at: seconds - segment.start, in: timeline)
    }

    /// Seconds from time 0 to the end.
    public func length(_ timeline: Timeline) -> Double {
        let last = segments[segments.count - 1]
        return last.start + last.run.length(timeline)
    }

    /// The same performance at `tempo` from the first bar line at or after `earliest`, up to the same end. A change
    /// not yet begun (starting at or after `earliest`) is replaced. Nil when no bar line is left before the end.
    public func retimed(_ tempo: Tempo, from earliest: Double, in timeline: Timeline) -> Performance? {
        let kept = segments.filter { $0.start < earliest }
        guard let current = kept.last else { return nil }
        let run = current.run
        let (origin, end) = (timeline.entries[run.from].start, run.end(timeline))
        let time = { (tick: Int) in current.start + run.seconds(atTick: tick, in: timeline) }
        guard
            let bar = timeline.bars.first(where: { $0.start > origin && $0.start < end && time($0.start) >= earliest }),
            let from = timeline.entries.firstIndex(where: { $0.start >= bar.start }),
            timeline.entries[from].start < end
        else { return nil }
        let next = Run(from: from, until: run.until, countInBars: 0, tempo: tempo)
        return Performance(segments: kept + [Segment(start: time(bar.start), run: next)])
    }

    private func segment(at seconds: Double) -> Segment {
        segments.last { $0.start <= seconds } ?? segments[0]
    }
}
