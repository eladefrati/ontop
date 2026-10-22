import CoreGraphics
import Testing
@testable import ontop

/// The pin sequence as PinManager runs it: toggle, the lookup's await, the ticket check, then
/// build and store. The lookup never finds the window, so a pin that gets past the ticket
/// check reports why, and a stale one says nothing.
@MainActor
struct PinManagerTests {
    private final class Counts {
        var lookups = 0
        var failures = 0
    }

    private let window = WindowInfo(id: 7, pid: 1, appName: "App", title: "Doc", frame: .zero, isCapturable: true)

    private func manager(_ counts: Counts) -> PinManager {
        let manager = PinManager(lookup: { window in
            counts.lookups += 1
            return .failure(.notOnScreen(title: window.title))
        })
        manager.onFailure = { counts.failures += 1 }
        return manager
    }

    /// Returns once `lookups` lookups have run, and with them the rest of their pins.
    private func settle(_ counts: Counts, lookups: Int) async {
        while counts.lookups < lookups { await Task.yield() }
        await Task.yield()
    }

    // Both presses of a 0 ms double press reach toggle before the first lookup finishes.
    @Test func aDoublePressLeavesTheWindowUnpinnedAndReportsNothing() async {
        let counts = Counts()
        let manager = manager(counts)
        manager.toggle(window)
        manager.toggle(window)
        #expect(!manager.isPinned(window.id))
        await settle(counts, lookups: 1)
        #expect(manager.failure == nil)
        #expect(counts.failures == 0)
        #expect(!manager.isPinned(window.id))
        #expect(!manager.hasPins)
    }

    @Test func aPressReportsWhyItsPinFailed() async {
        let counts = Counts()
        let manager = manager(counts)
        manager.toggle(window)
        #expect(manager.isPinned(window.id))
        await settle(counts, lookups: 1)
        #expect(manager.failure == .notOnScreen(title: "Doc"))
        #expect(counts.failures == 1)
        #expect(!manager.isPinned(window.id))
    }

    @Test func aThirdPressPinsOnItsOwnAndOnlyItReports() async {
        let counts = Counts()
        let manager = manager(counts)
        manager.toggle(window)
        manager.toggle(window)
        manager.toggle(window)
        await settle(counts, lookups: 2)
        #expect(manager.failure == .notOnScreen(title: "Doc"))
        #expect(counts.failures == 1)
    }

    @Test func theNextPressClearsTheFailureLine() async {
        let counts = Counts()
        let manager = manager(counts)
        manager.toggle(window)
        await settle(counts, lookups: 1)
        #expect(manager.failure != nil)
        manager.toggle(window)
        #expect(manager.failure == nil)
    }

    @Test func unpinAllClearsTheFailureLine() async {
        let counts = Counts()
        let manager = manager(counts)
        manager.toggle(window)
        await settle(counts, lookups: 1)
        #expect(manager.failure != nil)
        manager.unpinAll()
        #expect(manager.failure == nil)
    }
}
