import CoreGraphics
import Testing
@testable import ontop

@MainActor
struct StatusMenuTests {
    private func window(_ id: CGWindowID, _ appName: String) -> WindowInfo {
        WindowInfo(id: id, pid: 1, appName: appName, title: "w\(id)", frame: .zero)
    }

    @Test func groupsByAppInOrderOfEachAppsFrontmostWindow() {
        let groups = StatusMenu.groupedByApp([window(1, "Safari"), window(2, "Terminal"), window(3, "Safari")])
        #expect(groups.map(\.0) == ["Safari", "Terminal"])
        #expect(groups.map { $0.1.map(\.id) } == [[1, 3], [2]])
    }

    @Test func noWindowsGiveNoGroups() {
        #expect(StatusMenu.groupedByApp([]).isEmpty)
    }
}
