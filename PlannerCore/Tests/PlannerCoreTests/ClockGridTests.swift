import XCTest
@testable import PlannerCore

final class ClockGridTests: XCTestCase {
    func testFormatting() {
        XCTAssertEqual(ClockGrid.format(minutes: 0), "0:00")
        XCTAssertEqual(ClockGrid.format(minutes: 9 * 60 + 5), "9:05")
        XCTAssertEqual(ClockGrid.format(minutes: 14 * 60 + 30), "14:30")
        XCTAssertEqual(ClockGrid.format(minutes: 24 * 60), "24:00")
        XCTAssertEqual(ClockGrid.formatDuration(15), "15 мин")
        XCTAssertEqual(ClockGrid.formatDuration(60), "1 ч")
        XCTAssertEqual(ClockGrid.formatDuration(90), "1 ч 30 мин")
    }

    func testPointsConversion() {
        XCTAssertEqual(ClockGrid.points(forMinutes: 60), 56)
        XCTAssertEqual(ClockGrid.points(forMinutes: 30), 28)
        XCTAssertEqual(ClockGrid.minutes(forPoints: 56), 60)
        XCTAssertEqual(ClockGrid.minutes(forPoints: 14), 15)
    }

    func testSnappingAndClamping() {
        XCTAssertEqual(ClockGrid.snapped(97), 90)
        XCTAssertEqual(ClockGrid.snapped(98), 105)
        XCTAssertEqual(ClockGrid.clampedStart(-20, duration: 30), 0)
        XCTAssertEqual(ClockGrid.clampedStart(23 * 60 + 50, duration: 30), 23 * 60 + 30)
    }
}
