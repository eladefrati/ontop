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

    @Test func flipsARectOnADisplayLeftOfThePrimary() {
        let rect = Geometry.appKitRect(fromCG: CGRect(x: -1440, y: 0, width: 800, height: 600), primaryHeight: 900)
        #expect(rect == CGRect(x: -1440, y: 300, width: 800, height: 600))
    }
}
