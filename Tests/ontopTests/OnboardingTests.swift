import Testing
@testable import ontop

@MainActor
struct OnboardingTests {
    @Test func everythingGrantedAtLaunchIsReady() {
        #expect(Onboarding.step(accessibility: true, screenRecording: true, screenRecordingWasMissingAtLaunch: false) == .done(.ready))
    }

    @Test func screenRecordingGrantedAfterLaunchRelaunches() {
        #expect(Onboarding.step(accessibility: true, screenRecording: true, screenRecordingWasMissingAtLaunch: true) == .done(.relaunch))
    }

    @Test func accessibilityIsAskedFirst() {
        for screenRecording in [true, false] {
            for missingAtLaunch in [true, false] {
                #expect(Onboarding.step(accessibility: false, screenRecording: screenRecording,
                                        screenRecordingWasMissingAtLaunch: missingAtLaunch) == .needs(.accessibility))
            }
        }
    }

    @Test func screenRecordingIsAskedOnceAccessibilityIsGranted() {
        #expect(Onboarding.step(accessibility: true, screenRecording: false, screenRecordingWasMissingAtLaunch: true) == .needs(.screenRecording))
    }

    // The order a first launch goes through: nothing granted, then Accessibility, then Screen
    // Recording. Only the last step leaves onboarding, and it relaunches.
    @Test func aFirstLaunchEndsInARelaunch() {
        let steps = [(false, false), (true, false), (true, true)].map {
            Onboarding.step(accessibility: $0.0, screenRecording: $0.1, screenRecordingWasMissingAtLaunch: true)
        }
        #expect(steps == [.needs(.accessibility), .needs(.screenRecording), .done(.relaunch)])
    }
}
