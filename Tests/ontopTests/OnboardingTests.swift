import Testing
@testable import ontop

@MainActor
struct OnboardingTests {
    @Test func everythingGrantedIsReady() {
        #expect(Onboarding.step(accessibility: true, screenRecording: true) == .ready)
    }

    @Test func accessibilityIsAskedFirst() {
        for screenRecording in [true, false] {
            #expect(Onboarding.step(accessibility: false, screenRecording: screenRecording) == .needs(.accessibility))
        }
    }

    @Test func screenRecordingIsAskedOnceAccessibilityIsGranted() {
        #expect(Onboarding.step(accessibility: true, screenRecording: false) == .needs(.screenRecording))
    }
}
