import Testing
@testable import ontop

struct MirrorPlacementTests {
    private typealias Step = (next: MirrorPlacement, order: MirrorPlacement.Order)

    private func step(_ placement: MirrorPlacement, follows: Bool, onScreen: Bool) -> Step {
        placement.next(followsDesktops: follows, windowOnScreen: { onScreen })
    }

    @Test func pinnedWithFollowOnJoinsEveryDesktop() {
        let result = step(.notPlaced, follows: true, onScreen: true)
        #expect(result.next == .everyDesktop)
        #expect(result.order == .orderIn)
    }

    @Test func pinnedWithFollowOffJoinsTheWindowsDesktop() {
        let result = step(.notPlaced, follows: false, onScreen: true)
        #expect(result.next == .windowDesktop)
        #expect(result.order == .orderIn)
    }

    @Test func notPlacedWaitsWhileTheWindowIsOffScreen() {
        let result = step(.notPlaced, follows: false, onScreen: false)
        #expect(result.next == .notPlaced)
        #expect(result.order == .none)
    }

    @Test func followOffAtHomeKeepsTheMirrorWhereItIs() {
        let result = step(.everyDesktop, follows: false, onScreen: true)
        #expect(result.next == .windowDesktop)
        #expect(result.order == .none)
    }

    @Test func followOffAwayOrdersTheMirrorOut() {
        let result = step(.everyDesktop, follows: false, onScreen: false)
        #expect(result.next == .notPlaced)
        #expect(result.order == .orderOut)
    }

    @Test func windowDesktopStaysWithoutAskingTheWindowServer() {
        var asked = false
        let result = MirrorPlacement.windowDesktop.next(followsDesktops: false, windowOnScreen: { asked = true; return false })
        #expect(result.next == .windowDesktop)
        #expect(result.order == .none)
        #expect(!asked)
    }

    @Test func followOnFromTheWindowsDesktopNeedsNoReorder() {
        let result = step(.windowDesktop, follows: true, onScreen: false)
        #expect(result.next == .everyDesktop)
        #expect(result.order == .none)
    }

    @Test func anOrderedOutMirrorIsNeverOnTheActiveDesktop() {
        #expect(!MirrorPlacement.notPlaced.isOnActiveDesktop(windowOnScreen: { true }, mirrorOnActiveSpace: { true }))
    }

    @Test func aFollowingMirrorIsAlwaysOnTheActiveDesktop() {
        #expect(MirrorPlacement.everyDesktop.isOnActiveDesktop(windowOnScreen: { false }, mirrorOnActiveSpace: { false }))
    }

    @Test func aMirrorJustOrderedInIsOnTheActiveDesktopWhileItsWindowIsOnScreen() {
        #expect(MirrorPlacement.windowDesktop.isOnActiveDesktop(windowOnScreen: { true }, mirrorOnActiveSpace: { false }))
    }

    @Test func aMirrorOfAnOffScreenWindowFollowsItsOwnReport() {
        #expect(MirrorPlacement.windowDesktop.isOnActiveDesktop(windowOnScreen: { false }, mirrorOnActiveSpace: { true }))
        #expect(!MirrorPlacement.windowDesktop.isOnActiveDesktop(windowOnScreen: { false }, mirrorOnActiveSpace: { false }))
    }

    // Pinned at home, Follow on, go away, Follow off, switch away again, come home.
    @Test func followOffAwayOrdersTheMirrorInOnlyOnceBackHome() {
        var placement = step(.notPlaced, follows: false, onScreen: true).next
        placement = step(placement, follows: true, onScreen: true).next
        var orders: [MirrorPlacement.Order] = []
        for (follows, onScreen) in [(true, false), (false, false), (false, false), (false, true), (false, true)] {
            let result = step(placement, follows: follows, onScreen: onScreen)
            placement = result.next
            orders.append(result.order)
        }
        #expect(orders == [.none, .orderOut, .none, .orderIn, .none])
        #expect(placement == .windowDesktop)
    }
}
