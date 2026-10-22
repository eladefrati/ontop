import CoreGraphics
import ServiceManagement
import Testing
@testable import ontop

@MainActor
struct StatusMenuTests {
    private func window(_ id: CGWindowID, _ appName: String) -> WindowInfo {
        WindowInfo(id: id, pid: 1, appName: appName, title: "w\(id)", frame: .zero, isCapturable: true)
    }

    @Test func groupsByAppInOrderOfEachAppsFrontmostWindow() {
        let groups = StatusMenu.groupedByApp([window(1, "Safari"), window(2, "Terminal"), window(3, "Safari")])
        #expect(groups.map(\.0) == ["Safari", "Terminal"])
        #expect(groups.map { $0.1.map(\.id) } == [[1, 3], [2]])
    }

    @Test func noWindowsGiveNoGroups() {
        #expect(StatusMenu.groupedByApp([]).isEmpty)
    }

    @Test func launchAtLoginIsCheckedWhenEnabled() {
        #expect(StatusMenu.launchAtLoginState(.enabled) == .on)
    }

    @Test func launchAtLoginShowsADashWhileItWaitsForApproval() {
        #expect(StatusMenu.launchAtLoginState(.requiresApproval) == .mixed)
    }

    @Test(arguments: [SMAppService.Status.notRegistered, .notFound])
    func launchAtLoginIsUncheckedOtherwise(_ status: SMAppService.Status) {
        #expect(StatusMenu.launchAtLoginState(status) == .off)
    }
}

@MainActor
struct WaitingMenuTests {
    @Test(arguments: [(Permission.accessibility, "ontop needs Accessibility access"),
                      (Permission.screenRecording, "ontop needs Screen Recording access")])
    func namesTheMissingPermissionAndOffersItsSettings(_ permission: Permission, _ title: String) throws {
        let items = StatusMenu.waitingItems(permission, target: nil)
        let missing = try #require(items.first)
        #expect(missing.title == title)
        #expect(!missing.isEnabled)
        #expect(!(missing.subtitle ?? "").isEmpty)
        let open = try #require(items.first { $0.title == "Open System Settings\u{2026}" })
        #expect(open.isEnabled)
        #expect(open.action != nil)
    }
}
