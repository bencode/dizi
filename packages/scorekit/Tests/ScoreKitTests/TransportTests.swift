import Testing

@testable import ScoreKit

@Test(arguments: [
    (Transport.stopped(start: 3), Transport.Action.play, Transport.running(from: 3, start: 3)),
    (.stopped(start: 3), .select(7), .stopped(start: 7)),
    (.stopped(start: 3), .stop, .stopped(start: 3)),
    (.running(from: 3, start: 3), .pause(entry: 9), .paused(entry: 9, start: 3)),
    (.running(from: 9, start: 3), .stop, .stopped(start: 3)),
    (.running(from: 9, start: 3), .finish, .stopped(start: 3)),
    (.running(from: 3, start: 3), .select(7), .running(from: 3, start: 3)),
    (.paused(entry: 9, start: 3), .play, .running(from: 9, start: 3)),
    (.paused(entry: 9, start: 3), .stop, .stopped(start: 3)),
    (.paused(entry: 9, start: 3), .select(5), .paused(entry: 5, start: 5)),
])
func movesBetweenStates(_ state: Transport, _ action: Transport.Action, _ expected: Transport) {
    #expect(state.next(action) == expected)
}
