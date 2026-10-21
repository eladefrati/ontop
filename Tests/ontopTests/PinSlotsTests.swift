import CoreGraphics
import Testing
@testable import ontop

struct PinSlotsTests {
    private typealias Slots = PinSlots<Int>

    private func ticket(_ toggle: Slots.Toggle) -> Slots.Ticket? {
        if case .resolve(let ticket) = toggle { ticket } else { nil }
    }

    @Test func aToggleCountsAsPinnedWhileItResolves() throws {
        var slots = Slots()
        let first = try #require(ticket(slots.toggle(7)))
        #expect(slots.isCurrent(first))
        #expect(slots.contains(7))
        #expect(!slots.isEmpty)
        #expect(slots.values.isEmpty)
    }

    @Test func aStoredValueIsUnpinnedByTheNextToggle() throws {
        var slots = Slots()
        let first = try #require(ticket(slots.toggle(7)))
        slots.store(42, for: first)
        #expect(slots.values == [42])
        guard case .unpinned(let value) = slots.toggle(7) else {
            Issue.record("second toggle did not unpin")
            return
        }
        #expect(value == 42)
        #expect(slots.isEmpty)
    }

    // Both presses of a 0 ms double press reach the slots before either resolve finishes.
    @Test func twoTogglesWhileResolvingLeaveTheWindowUnpinned() {
        var slots = Slots()
        let tickets = [slots.toggle(7), slots.toggle(7)].compactMap(ticket)
        let current = tickets.filter(slots.isCurrent)
        for (value, ticket) in current.enumerated() { slots.store(value, for: ticket) }
        #expect(current.isEmpty)
        #expect(!slots.contains(7))
    }

    @Test func aThirdToggleWhileTheFirstResolvesPinsWithItsOwnTicket() throws {
        var slots = Slots()
        let first = try #require(ticket(slots.toggle(7)))
        guard case .cancelled = slots.toggle(7) else {
            Issue.record("second toggle did not cancel")
            return
        }
        let third = try #require(ticket(slots.toggle(7)))
        #expect(!slots.isCurrent(first))
        #expect(slots.isCurrent(third))
        slots.store(3, for: third)
        #expect(slots.values == [3])
    }

    @Test func aResolveFinishingAfterRemoveAllIsStale() throws {
        var slots = Slots()
        let pending = try #require(ticket(slots.toggle(7)))
        slots.store(5, for: try #require(ticket(slots.toggle(9))))
        #expect(slots.removeAll() == [5])
        #expect(!slots.isCurrent(pending))
        #expect(!slots.contains(7))
    }

    @Test func ticketsForDifferentWindowsDoNotInterfere() throws {
        var slots = Slots()
        let seven = try #require(ticket(slots.toggle(7)))
        let nine = try #require(ticket(slots.toggle(9)))
        slots.store(9, for: nine)
        #expect(slots.isCurrent(seven))
        slots.store(7, for: seven)
        #expect(slots.values.sorted() == [7, 9])
    }

    @Test func removingAResolvingSlotFreesTheWindow() throws {
        var slots = Slots()
        let failed = try #require(ticket(slots.toggle(7)))
        #expect(slots.remove(7) == nil)
        #expect(!slots.isCurrent(failed))
        #expect(ticket(slots.toggle(7)) != nil)
    }

    @Test func removeAllReturnsTheStoredValues() throws {
        var slots = Slots()
        slots.store(1, for: try #require(ticket(slots.toggle(7))))
        slots.store(2, for: try #require(ticket(slots.toggle(9))))
        #expect(slots.removeAll().sorted() == [1, 2])
        #expect(slots.isEmpty)
    }

    @Test func removeIsIdempotent() throws {
        var slots = Slots()
        slots.store(5, for: try #require(ticket(slots.toggle(9))))
        #expect(slots.remove(9) == 5)
        #expect(slots.remove(9) == nil)
    }

    @Test func idsWhereMatchesPinnedValuesOnly() throws {
        var slots = Slots()
        slots.store(1, for: try #require(ticket(slots.toggle(7))))
        slots.store(2, for: try #require(ticket(slots.toggle(9))))
        _ = slots.toggle(11)
        #expect(slots.ids(where: { $0 == 2 }) == [9])
        #expect(slots.ids(where: { _ in true }).sorted() == [7, 9])
    }
}
