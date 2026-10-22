import CoreGraphics
import Testing
@testable import ontop

@MainActor
struct ClickForwarderTests {
    private let point = CGPoint(x: 100, y: 200)

    private func event(_ type: CGEventType, button: CGMouseButton = .left,
                       flags: CGEventFlags = [], at location: CGPoint? = nil) -> CGEvent {
        let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: location ?? point, mouseButton: button)!
        event.flags = flags
        return event
    }

    private func forwarder(_ posted: Posted) -> ClickForwarder {
        ClickForwarder(point: point, post: { posted.events.append($0) })
    }

    final class Posted {
        var events: [CGEvent] = []
    }

    @Test func recordsUntilTheButtonIsUp() {
        let forwarder = forwarder(Posted())
        forwarder.record(event(.leftMouseDown))
        #expect(forwarder.isRecording)
        #expect(!forwarder.isComplete)
        forwarder.record(event(.leftMouseUp))
        #expect(!forwarder.isRecording)
        #expect(forwarder.isComplete)
    }

    @Test func theRightButtonCountsLikeTheLeft() {
        let forwarder = forwarder(Posted())
        forwarder.record(event(.rightMouseDown, button: .right))
        #expect(forwarder.isRecording)
        forwarder.record(event(.rightMouseUp, button: .right))
        #expect(forwarder.isComplete)
    }

    @Test func deliversTheWholeGestureInOrderAtItsPoints() async {
        let posted = Posted()
        let forwarder = forwarder(posted)
        let end = CGPoint(x: 300, y: 260)
        forwarder.record(event(.leftMouseDown))
        forwarder.record(event(.leftMouseDragged, at: end))
        forwarder.record(event(.leftMouseUp, at: end))
        #expect(await forwarder.deliver(when: { true }))
        #expect(posted.events.map(\.type) == [.leftMouseDown, .leftMouseDragged, .leftMouseUp])
        #expect(posted.events.map(\.location) == [point, end, end])
    }

    @Test func modifierKeysAndTheButtonAreKept() async {
        let posted = Posted()
        let forwarder = forwarder(posted)
        forwarder.record(event(.rightMouseDown, button: .right, flags: .maskCommand))
        forwarder.record(event(.rightMouseUp, button: .right, flags: .maskCommand))
        _ = await forwarder.deliver(when: { true })
        #expect(posted.events.allSatisfy { $0.flags.contains(.maskCommand) })
        #expect(posted.events.map(\.type) == [.rightMouseDown, .rightMouseUp])
    }

    @Test func aWindowThatNeverComesForwardGetsNothing() async {
        let posted = Posted()
        let forwarder = forwarder(posted)
        forwarder.record(event(.leftMouseDown))
        forwarder.record(event(.leftMouseUp))
        #expect(await forwarder.deliver(deadline: .milliseconds(50), when: { false }) == false)
        #expect(posted.events.isEmpty)
    }

    @Test func deliversOnceTheWindowComesForward() async {
        let posted = Posted()
        let forwarder = forwarder(posted)
        forwarder.record(event(.leftMouseDown))
        forwarder.record(event(.leftMouseUp))
        var checks = 0
        #expect(await forwarder.deliver(when: { checks += 1; return checks == 3 }))
        #expect(posted.events.count == 2)
    }

    @Test func cancelledDeliveryPostsNothing() async {
        let posted = Posted()
        let forwarder = forwarder(posted)
        forwarder.record(event(.leftMouseDown))
        forwarder.record(event(.leftMouseUp))
        var checks = 0
        let delivered = await forwarder.deliver(when: {
            checks += 1
            if checks == 2 { forwarder.cancel() }
            return false
        })
        #expect(!delivered)
        #expect(posted.events.isEmpty)
    }

    @Test func aSecondGestureIsIgnored() async {
        let posted = Posted()
        let forwarder = forwarder(posted)
        forwarder.record(event(.leftMouseDown))
        forwarder.record(event(.leftMouseUp))
        forwarder.record(event(.leftMouseDown))
        forwarder.record(event(.leftMouseUp))
        #expect(forwarder.isComplete)
        _ = await forwarder.deliver(when: { true })
        #expect(posted.events.count == 2)
    }

    @Test func aDragOrUpBeforeAnyDownIsIgnored() {
        let forwarder = forwarder(Posted())
        forwarder.record(event(.leftMouseDragged))
        forwarder.record(event(.leftMouseUp))
        #expect(!forwarder.isRecording)
        #expect(!forwarder.isComplete)
    }
}
