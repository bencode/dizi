import Testing

@testable import ScoreKit

// 茉莉花 in 2/4 at ♩=60: a bar is 2 s, and the run starts after a 2 s count-in.
private let slow = Tempo(bpm: 60, beat: 480)
private let fast = Tempo(bpm: 120, beat: 480)

@Test func changesTheTempoFromTheNextBarLine() throws {
    let score = try molihua()
    let timeline = Timeline(score: score)
    let run = Run(from: 0, tempo: slow)
    let changed = try #require(Performance(run).retimed(fast, from: 3, in: timeline))
    let bar = try #require(timeline.bars.first { $0.start > 0 })
    let first = try #require(timeline.entries.firstIndex { $0.start >= bar.start })

    // The bar after the first starts 4 s in: 2 s of count-in and one bar.
    #expect(changed.segments.last?.start == 4)
    #expect(changed.position(at: 3.9, in: timeline) == run.position(at: 3.9, in: timeline))
    #expect(changed.position(at: 4, in: timeline) == .entry(first, progress: 0))
    // Half a second at ♩=120 is a beat.
    let beatLater = try #require(timeline.entry(at: bar.start + 480))
    #expect(changed.position(at: 4.5, in: timeline) == .entry(beatLater, progress: 0))
    #expect(changed.length(timeline) == 4 + Run(from: first, countInBars: 0, tempo: fast).length(timeline))
}

@Test func replacesAChangeThatHasNotBegun() throws {
    let timeline = Timeline(score: try molihua())
    let medium = Tempo(bpm: 90, beat: 480)
    let once = try #require(Performance(Run(from: 0, tempo: slow)).retimed(fast, from: 3, in: timeline))
    let twice = try #require(once.retimed(medium, from: 3.5, in: timeline))

    #expect(twice.segments.count == 2)
    #expect(twice.segments.last?.start == 4)
    #expect(twice.segments.last?.run.tempo == medium)
}

@Test func keepsTheTempoWhenNoBarLineIsLeft() throws {
    let timeline = Timeline(score: try molihua())
    let run = Run(from: 0, tempo: slow)

    #expect(Performance(run).retimed(fast, from: run.length(timeline) - 1, in: timeline) == nil)
}
