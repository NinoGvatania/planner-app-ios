import XCTest
@testable import PlannerCore

final class DayLayoutTests: XCTestCase {
    private func placement(_ id: String, in result: [LanePlacement]) -> LanePlacement? {
        result.first { $0.id == id }
    }

    func testNonOverlappingTasksGetFullWidth() {
        let result = DayLayout.lanes(for: [
            LayoutItem(id: "a", start: 10 * 60, duration: 60),
            LayoutItem(id: "b", start: 12 * 60, duration: 30),
        ])
        XCTAssertEqual(placement("a", in: result), LanePlacement(id: "a", lane: 0, laneCount: 1))
        XCTAssertEqual(placement("b", in: result), LanePlacement(id: "b", lane: 0, laneCount: 1))
    }

    func testOverlappingTasksShareColumns() {
        let result = DayLayout.lanes(for: [
            LayoutItem(id: "a", start: 10 * 60, duration: 60),
            LayoutItem(id: "b", start: 10 * 60 + 30, duration: 60),
            LayoutItem(id: "c", start: 12 * 60, duration: 60),
        ])
        XCTAssertEqual(placement("a", in: result), LanePlacement(id: "a", lane: 0, laneCount: 2))
        XCTAssertEqual(placement("b", in: result), LanePlacement(id: "b", lane: 1, laneCount: 2))
        XCTAssertEqual(placement("c", in: result), LanePlacement(id: "c", lane: 0, laneCount: 1))
    }

    func testAdjacentShortTasksDoNotOverlapVisually() {
        // Две 15‑минутные подряд: на экране каждая не меньше 24 pt, поэтому встают рядом.
        let result = DayLayout.lanes(for: [
            LayoutItem(id: "a", start: 9 * 60, duration: 15),
            LayoutItem(id: "b", start: 9 * 60 + 15, duration: 15),
        ])
        XCTAssertEqual(placement("a", in: result)?.laneCount, 2)
        XCTAssertEqual(placement("b", in: result)?.lane, 1)
    }

    func testLongerTaskComesFirstAtSameStart() {
        let result = DayLayout.lanes(for: [
            LayoutItem(id: "short", start: 14 * 60, duration: 30),
            LayoutItem(id: "long", start: 14 * 60, duration: 120),
        ])
        XCTAssertEqual(placement("long", in: result)?.lane, 0)
        XCTAssertEqual(placement("short", in: result)?.lane, 1)
    }

    func testThreeWayOverlap() {
        let result = DayLayout.lanes(for: [
            LayoutItem(id: "a", start: 17 * 60, duration: 7 * 60),
            LayoutItem(id: "b", start: 17 * 60, duration: 30),
            LayoutItem(id: "c", start: 19 * 60, duration: 60),
        ])
        XCTAssertEqual(placement("a", in: result)?.laneCount, 2)
        XCTAssertEqual(placement("c", in: result)?.lane, 1)
    }
}
