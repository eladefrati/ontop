import CoreGraphics

/// The pin slot of every window. Pinning is asynchronous: a ScreenCaptureKit lookup sits
/// between the toggle and the stored value. The toggle claims the slot at once, so toggles
/// alternate pin, unpin, pin however fast they come: the second of two presses at 0 ms
/// cancels the first, whose resolve then finds its ticket stale and builds nothing.
///
/// Generic over the pinned value so the tests run it without AppKit or ScreenCaptureKit.
struct PinSlots<Value> {
    /// Issued when a toggle starts a resolve. Only the window's newest ticket is current.
    struct Ticket: Equatable {
        let windowID: CGWindowID
        fileprivate let serial: UInt64
    }

    enum Toggle {
        /// The window had no slot. Resolve it; store only while `isCurrent(ticket)`.
        case resolve(Ticket)
        /// The window was still resolving. Its resolve will find its ticket stale.
        case cancelled
        /// The window was pinned. The slot is gone; the caller ends the value.
        case unpinned(Value)
    }

    private enum Slot {
        case resolving(Ticket)
        case pinned(Value)
    }

    private var slots: [CGWindowID: Slot] = [:]
    private var lastSerial: UInt64 = 0

    mutating func toggle(_ id: CGWindowID) -> Toggle {
        switch slots.removeValue(forKey: id) {
        case nil:
            lastSerial += 1
            let ticket = Ticket(windowID: id, serial: lastSerial)
            slots[id] = .resolving(ticket)
            return .resolve(ticket)
        case .resolving:
            return .cancelled
        case .pinned(let value):
            return .unpinned(value)
        }
    }

    /// True while the ticket's resolve still owns its window's slot: not toggled off, not
    /// removed, not superseded by a newer toggle.
    func isCurrent(_ ticket: Ticket) -> Bool {
        if case .resolving(let current) = slots[ticket.windowID] { current == ticket } else { false }
    }

    /// The caller checks `isCurrent` and builds the value with no await in between, so a
    /// stale resolve never builds anything.
    mutating func store(_ value: Value, for ticket: Ticket) {
        precondition(isCurrent(ticket), "stored a value for a stale ticket")
        slots[ticket.windowID] = .pinned(value)
    }

    /// Clears the window's slot. Returns the pinned value, or nil when it was resolving or empty.
    mutating func remove(_ id: CGWindowID) -> Value? {
        if case .pinned(let value) = slots.removeValue(forKey: id) { value } else { nil }
    }

    /// Clears every slot, resolving ones included. Returns the pinned values.
    mutating func removeAll() -> [Value] {
        defer { slots.removeAll() }
        return values
    }

    /// True for resolving and pinned slots alike: from the user's side the window is pinned
    /// from the press on.
    func contains(_ id: CGWindowID) -> Bool {
        slots[id] != nil
    }

    var isEmpty: Bool { slots.isEmpty }

    /// Pinned values only.
    var values: [Value] {
        slots.values.compactMap { if case .pinned(let value) = $0 { value } else { nil } }
    }

    /// Windows whose pinned value matches.
    func ids(where predicate: (Value) -> Bool) -> [CGWindowID] {
        slots.compactMap { id, slot in
            if case .pinned(let value) = slot, predicate(value) { id } else { nil }
        }
    }
}
