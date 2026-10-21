import Testing
@testable import ontop

struct MirrorVisibilityTests {
    @Test func hiddenWhileTheRealWindowIsInFront() {
        #expect(!MirrorVisibility.wanted(realWindowInFront: true, onActiveDesktop: true))
    }

    @Test func shownWhileAnotherWindowIsInFront() {
        #expect(MirrorVisibility.wanted(realWindowInFront: false, onActiveDesktop: true))
    }

    @Test func hiddenOffTheActiveDesktop() {
        #expect(!MirrorVisibility.wanted(realWindowInFront: false, onActiveDesktop: false))
        #expect(!MirrorVisibility.wanted(realWindowInFront: true, onActiveDesktop: false))
    }
}
