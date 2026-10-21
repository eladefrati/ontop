import CoreGraphics
import Testing
@testable import ontop

struct PinSlotsTests {
    private typealias Slots = PinSlots<Int>

    private func ticket(_ toggle: Slots.Toggle) -> Slots.Ticket? {
        if case .resolve(let ticket) = toggle { ticket } else { nil }
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
        withKnownIssue("the second toggle does not see the first one's resolve") {
            #expect(current.isEmpty)
            #expect(!slots.contains(7))
        }
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

    @Test func idsWhereMatchesStoredValues() throws {
        var slots = Slots()
        slots.store(1, for: try #require(ticket(slots.toggle(7))))
        slots.store(2, for: try #require(ticket(slots.toggle(9))))
        #expect(slots.ids(where: { $0 == 2 }) == [9])
    }
}
