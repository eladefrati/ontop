import Testing
@testable import ontop

struct MirrorStreamTests {
    @Test func showingStartsWithoutFrames() {
        let (next, effect) = MirrorStream.hidden.on(.show)
        #expect(next == .starting(failures: 0))
        #expect(effect == .show)
        #expect(!next.showsFrames)
    }

    @Test func theFirstFrameMakesTheMirrorOpaque() {
        let (next, effect) = MirrorStream.starting(failures: 0).on(.frame)
        #expect(next == .live)
        #expect(effect == nil)
        #expect(next.showsFrames)
    }

    @Test func aFailedStartIsRetriedWithNothingShown() {
        let (next, effect) = MirrorStream.starting(failures: 0).on(.startFailed)
        #expect(next == .starting(failures: 1))
        #expect(effect == .retry(after: .milliseconds(500)))
        #expect(!next.showsFrames)
    }

    @Test func retriesBackOff() {
        let (next, effect) = MirrorStream.starting(failures: 2).on(.startFailed)
        #expect(next == .starting(failures: 3))
        #expect(effect == .retry(after: .milliseconds(1500)))
    }

    @Test func theFourthFailedStartInARowGivesUp() {
        let (next, effect) = MirrorStream.starting(failures: 3).on(.startFailed)
        #expect(next == .hidden)
        #expect(effect == .giveUp)
    }

    @Test func aStoppedStreamKeepsTheLastFrameWhileItRestarts() {
        let (next, effect) = MirrorStream.live.on(.stopped)
        #expect(next == .restarting(failures: 1))
        #expect(effect == .retry(after: .milliseconds(500)))
        #expect(next.showsFrames)
    }

    @Test func aFailedRestartCounts() {
        let (next, effect) = MirrorStream.restarting(failures: 1).on(.startFailed)
        #expect(next == .restarting(failures: 2))
        #expect(effect == .retry(after: .milliseconds(1000)))
    }

    @Test func theFourthFailedRestartInARowGivesUp() {
        let (next, effect) = MirrorStream.restarting(failures: 3).on(.stopped)
        #expect(next == .hidden)
        #expect(effect == .giveUp)
    }

    @Test func aFrameResetsTheFailureCount() {
        let live = MirrorStream.restarting(failures: 2).on(.frame).next
        #expect(live == .live)
        #expect(live.on(.stopped).next == .restarting(failures: 1))
    }

    @Test func hidingStopsTheStreamFromAnyShownState() {
        for state in [MirrorStream.starting(failures: 1), .live, .restarting(failures: 2)] {
            let (next, effect) = state.on(.hide)
            #expect(next == .hidden)
            #expect(effect == .stop)
        }
    }

    @Test func callbacksAfterAHideAreIgnored() {
        for event in [MirrorStream.Event.hide, .frame, .startFailed, .stopped] {
            let (next, effect) = MirrorStream.hidden.on(event)
            #expect(next == .hidden)
            #expect(effect == nil)
        }
    }

    @Test func showingAgainWhileShownChangesNothing() {
        for state in [MirrorStream.live, .starting(failures: 1)] {
            let (next, effect) = state.on(.show)
            #expect(next == state)
            #expect(effect == nil)
        }
    }
}
