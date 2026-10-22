import CoreGraphics
import Testing
@testable import ontop

struct WindowMatchTests {
    private let frame = CGRect(x: 100, y: 200, width: 640, height: 420)

    private func standard(_ frame: CGRect, _ title: String? = nil) -> AXWindowShape {
        AXWindowShape(frame: frame, title: title, subrole: "AXStandardWindow")
    }

    @Test func matchesAStandardWindowWithTheSameFrame() {
        #expect(WindowMatch.index(frame: frame, title: "a", in: [standard(frame)]) == 0)
    }

    @Test func toleratesLessThanTwoPointsOnEveryEdge() {
        let near = CGRect(x: 101.5, y: 198.5, width: 641.5, height: 418.5)
        #expect(WindowMatch.index(frame: frame, title: nil, in: [standard(near)]) == 0)
        let off = CGRect(x: 102.5, y: 200, width: 640, height: 420)
        #expect(WindowMatch.index(frame: frame, title: nil, in: [standard(off)]) == nil)
    }

    // macOS adds this helper to an app while one of its windows is being captured.
    @Test func neverMatchesTheCaptureHelperDialog() {
        let helper = AXWindowShape(frame: frame, title: "Window", subrole: "AXDialog")
        #expect(WindowMatch.index(frame: frame, title: "Window", in: [helper]) == nil)
        #expect(WindowMatch.index(frame: frame, title: "a", in: [helper, standard(frame)]) == 1)
    }

    @Test func theTitleBreaksATieBetweenWindowsWithTheSameFrame() {
        let twins = [standard(frame, "a"), standard(frame, "b")]
        #expect(WindowMatch.index(frame: frame, title: "b", in: twins) == 1)
        #expect(WindowMatch.index(frame: frame, title: nil, in: twins) == 0)
        #expect(WindowMatch.index(frame: frame, title: "c", in: twins) == 0)
    }

    @Test func noCandidatesMatchNothing() {
        #expect(WindowMatch.index(frame: frame, title: "a", in: []) == nil)
    }
}
