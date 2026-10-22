import CoreGraphics
import Foundation
import Testing
@testable import ontop

struct WindowListTests {
    private let ownPID: pid_t = 99

    // Shaped like CGWindowListCopyWindowInfo's entries: numbers arrive as NSNumber.
    private func entry(id: Int, pid: Int = 1, layer: Int = 0, alpha: Double? = 1, title: String? = "Doc",
                       bounds: [String: Double]? = ["X": 10, "Y": 20, "Width": 300, "Height": 200],
                       sharing: Int? = 1) -> [String: Any] {
        var info: [String: Any] = [
            kCGWindowNumber as String: NSNumber(value: id),
            kCGWindowOwnerPID as String: NSNumber(value: pid),
            kCGWindowOwnerName as String: "App",
            kCGWindowLayer as String: NSNumber(value: layer),
        ]
        info[kCGWindowAlpha as String] = alpha.map { NSNumber(value: $0) }
        info[kCGWindowName as String] = title
        info[kCGWindowBounds as String] = bounds?.mapValues { NSNumber(value: $0) }
        info[kCGWindowSharingState as String] = sharing.map { NSNumber(value: $0) }
        return info
    }

    private func ids(_ raw: [[String: Any]]) -> [CGWindowID] {
        WindowList.parse(raw, ownPID: ownPID).map(\.id)
    }

    @Test func keepsANormalWindowWithItsFrame() throws {
        let window = try #require(WindowList.parse([entry(id: 5)], ownPID: ownPID).first)
        #expect(window.id == 5)
        #expect(window.pid == 1)
        #expect(window.title == "Doc")
        #expect(window.frame == CGRect(x: 10, y: 20, width: 300, height: 200))
    }

    @Test func dropsOntopsOwnWindows() {
        #expect(ids([entry(id: 5, pid: Int(ownPID))]).isEmpty)
    }

    @Test func keepsOnlyNormalLevelWindows() {
        #expect(ids([entry(id: 5, layer: 3), entry(id: 6, layer: 0)]) == [6])
    }

    @Test func dropsTransparentWindowsAndKeepsOnesWithoutAlpha() {
        #expect(ids([entry(id: 5, alpha: 0), entry(id: 6, alpha: nil)]) == [6])
    }

    @Test func dropsUntitledWindows() {
        #expect(ids([entry(id: 5, title: nil), entry(id: 6, title: "")]).isEmpty)
    }

    @Test func dropsWindowsWithoutBounds() {
        #expect(ids([entry(id: 5, bounds: nil)]).isEmpty)
    }

    @Test func aWindowItsAppMarksNotSharedIsNotCapturable() {
        let windows = WindowList.parse([entry(id: 5, sharing: 0), entry(id: 6, sharing: 1), entry(id: 7, sharing: nil)],
                                       ownPID: ownPID)
        #expect(windows.map(\.isCapturable) == [false, true, true])
    }

    @Test func keepsTheWindowServersFrontToBackOrder() {
        #expect(ids([entry(id: 9), entry(id: 3), entry(id: 7)]) == [9, 3, 7])
    }

    @Test func aShownMirrorAboveTheWindowIsTheTopWindow() {
        let raw = [entry(id: 4, layer: 3), entry(id: 5)]
        #expect(WindowList.topWindow(at: CGPoint(x: 100, y: 100), in: raw) == 4)
    }

    @Test func aHiddenMirrorIsSkipped() {
        let raw = [entry(id: 4, layer: 3, alpha: 0), entry(id: 5)]
        #expect(WindowList.topWindow(at: CGPoint(x: 100, y: 100), in: raw) == 5)
    }

    @Test func aPointOutsideEveryWindowHasNoTopWindow() {
        #expect(WindowList.topWindow(at: CGPoint(x: 5, y: 5), in: [entry(id: 5)]) == nil)
    }

    @Test func theBottomRightEdgeIsOutsideTheWindow() {
        #expect(WindowList.topWindow(at: CGPoint(x: 310, y: 220), in: [entry(id: 5)]) == nil)
    }
}
