import Testing
@testable import ontop

struct PinFailureTests {
    @Test(arguments: [PinFailure.notCapturable(title: "Notes"), .notOnScreen(title: "Notes"),
                      .notAccessible(title: "Notes"), .contentUnavailable(title: "Notes")])
    func aFailedPinNamesTheWindowThenTheReason(_ failure: PinFailure) {
        #expect(failure.message.hasPrefix("Could not pin \u{201C}Notes\u{201D}: "))
        #expect(failure.message.count > "Could not pin \u{201C}Notes\u{201D}: ".count)
    }

    @Test func notCapturableAndNotOnScreenGiveDifferentReasons() {
        #expect(PinFailure.notCapturable(title: "Notes").message != PinFailure.notOnScreen(title: "Notes").message)
    }

    @Test func anEndedPinSaysItIsNoLongerPinned() {
        #expect(PinFailure.captureStopped(title: "Notes").message.hasPrefix("\u{201C}Notes\u{201D} is no longer pinned: "))
    }

    @Test func anUndeliveredClickNamesTheWindow() {
        #expect(PinFailure.clickNotDelivered(title: "Notes").message.hasPrefix("Could not click in \u{201C}Notes\u{201D}: "))
    }

    @Test func nothingInFrontSaysThereIsNothingToPin() {
        #expect(PinFailure.noWindow.message.hasPrefix("Nothing to pin: "))
    }
}
