/// Where 走谱 stands. A pure value: `next(_:)` gives the state after an action; nothing else changes it.
/// Entry numbers index `Timeline.entries`. Counting in and playing are both `running`; which one it is
/// follows from the clock (`Run.position`).
public enum Transport: Sendable, Equatable {
    /// `start` is the note a run begins from.
    case stopped(start: Int)
    /// Running from `from`; a stop returns to `start`.
    case running(from: Int, start: Int)
    /// Paused on `entry`; resuming runs from there, a stop returns to `start`.
    case paused(entry: Int, start: Int)

    /// The note a stop returns to.
    public var start: Int {
        switch self {
        case .stopped(let start), .running(_, let start), .paused(_, let start): start
        }
    }

    public enum Action: Sendable, Equatable {
        case play
        /// Pause on the entry sounding now.
        case pause(entry: Int)
        case stop
        /// The run reached the end of the score.
        case finish
        /// The player tapped a note.
        case select(Int)
    }

    public func next(_ action: Action) -> Transport {
        switch (self, action) {
        case (.stopped(let start), .play): .running(from: start, start: start)
        case (.stopped, .select(let entry)): .stopped(start: entry)
        case (.running(_, let start), .pause(let entry)): .paused(entry: entry, start: start)
        case (.running(_, let start), .stop), (.running(_, let start), .finish): .stopped(start: start)
        case (.paused(let entry, let start), .play): .running(from: entry, start: start)
        case (.paused(_, let start), .stop): .stopped(start: start)
        case (.paused, .select(let entry)): .paused(entry: entry, start: entry)
        case (.stopped, .pause), (.stopped, .stop), (.stopped, .finish),
            (.running, .play), (.running, .select),
            (.paused, .pause), (.paused, .finish):
            self
        }
    }
}
