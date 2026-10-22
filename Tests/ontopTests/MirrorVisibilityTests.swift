import Testing
@testable import ontop

struct MirrorVisibilityTests {
    @Test func hiddenWhileTheRealWindowIsInFront() {
        #expect(!MirrorVisibility.wanted(realWindowInFront: true, onActiveDesktop: true, recordingClick: false))
    }

    @Test func shownWhileAnotherWindowIsInFront() {
        #expect(MirrorVisibility.wanted(realWindowInFront: false, onActiveDesktop: true, recordingClick: false))
    }

    @Test func hiddenOffTheActiveDesktop() {
        #expect(!MirrorVisibility.wanted(realWindowInFront: false, onActiveDesktop: false, recordingClick: false))
        #expect(!MirrorVisibility.wanted(realWindowInFront: true, onActiveDesktop: false, recordingClick: false))
    }

    @Test func shownWhileAClickOnItHasAButtonDownEvenWithTheRealWindowInFront() {
        #expect(MirrorVisibility.wanted(realWindowInFront: true, onActiveDesktop: true, recordingClick: true))
    }
}
