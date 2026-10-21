import CoreGraphics

/// The pin of every window. Pinning is asynchronous: a ScreenCaptureKit lookup sits between
/// the toggle and the stored value, so a toggle hands out a ticket that the resolve stores
/// its value with.
///
/// Generic over the pinned value so the tests run it without AppKit or ScreenCaptureKit.
struct PinSlots<Value> {
    struct Ticket: Equatable {
        let windowID: CGWindowID
    }

    enum Toggle {
        /// The window had no value. Resolve it, then `store` with this ticket.
        case resolve(Ticket)
        /// The window was pinned. The slot is gone; the caller ends the value.
        case unpinned(Value)
    }

    private var slots: [CGWindowID: Value] = [:]

    mutating func toggle(_ id: CGWindowID) -> Toggle {
        if let value = slots.removeValue(forKey: id) { return .unpinned(value) }
        return .resolve(Ticket(windowID: id))
    }

    /// True while the ticket's window has no value.
    func isCurrent(_ ticket: Ticket) -> Bool {
        slots[ticket.windowID] == nil
    }

    mutating func store(_ value: Value, for ticket: Ticket) {
        slots[ticket.windowID] = value
    }

    /// Clears the window's slot and returns its value.
    mutating func remove(_ id: CGWindowID) -> Value? {
        slots.removeValue(forKey: id)
    }

    /// Clears every slot and returns the values.
    mutating func removeAll() -> [Value] {
        defer { slots.removeAll() }
        return Array(slots.values)
    }

    func contains(_ id: CGWindowID) -> Bool {
        slots[id] != nil
    }

    var isEmpty: Bool { slots.isEmpty }

    var values: [Value] { Array(slots.values) }

    /// Windows whose value matches.
    func ids(where predicate: (Value) -> Bool) -> [CGWindowID] {
        slots.filter { predicate($0.value) }.map(\.key)
    }
}
