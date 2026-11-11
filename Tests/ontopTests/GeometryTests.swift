import CoreGraphics
import Testing
@testable import ontop

@MainActor
struct GeometryTests {
    @Test func flipsARectOnThePrimaryDisplay() {
        let rect = Geometry.appKitRect(fromCG: CGRect(x: 10, y: 20, width: 300, height: 200), primaryHeight: 1000)
        #expect(rect == CGRect(x: 10, y: 780, width: 300, height: 200))
    }

    @Test func flipsARectOnADisplayAboveThePrimary() {
        let rect = Geometry.appKitRect(fromCG: CGRect(x: 0, y: -500, width: 100, height: 100), primaryHeight: 1000)
        #expect(rect == CGRect(x: 0, y: 1400, width: 100, height: 100))
    }

    // As measured: a 640 x 420 window with an 880 pt wide sheet, in a 640 x 420 stream.
    @Test func aScaledFrameGivesTheSizeOfTheWindowWithItsSheet() {
        let size = Geometry.contentSize(rect: CGRect(x: 0, y: 0, width: 640.0000190734863, height: 375.2727384567261),
                                        scale: 0.7272727489471436)
        #expect(size == CGSize(width: 880, height: 516))
    }

    @Test func anUnscaledFrameGivesItsOwnSize() {
        #expect(Geometry.contentSize(rect: CGRect(x: 0, y: 0, width: 640, height: 420), scale: 1) == CGSize(width: 640, height: 420))
    }

    @Test func flipsARectOnADisplayLeftOfThePrimary() {
        let rect = Geometry.appKitRect(fromCG: CGRect(x: -1440, y: 0, width: 800, height: 600), primaryHeight: 900)
        #expect(rect == CGRect(x: -1440, y: 300, width: 800, height: 600))
    }
}
