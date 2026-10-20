import XCTest
@testable import PlannerCore

final class FreeSlotSchedulerTests: XCTestCase {
    private func t(_ h: Int, _ m: Int = 0) -> Int { h * 60 + m }

    func testImportantFirstFromNextQuarterHour() {
        // Как в прототипе: сейчас 13:40, занято 14:30–16:00.
        let placements = FreeSlotScheduler.fit(
            [
                SchedulingCandidate(id: "o1", duration: 30, quadrant: .urgent, order: -1),
                SchedulingCandidate(id: "o2", duration: 30, quadrant: .urgentImportant, order: -2),
                SchedulingCandidate(id: "o3", duration: 15, quadrant: .urgent, order: -3),
            ],
            busy: [BusyInterval(start: t(14, 30), end: t(16))],
            from: t(13, 40)
        )
        XCTAssertEqual(placements, [
            Placement(id: "o2", start: t(13, 45)),
            Placement(id: "o3", start: t(14, 15)),
            Placement(id: "o1", start: t(16)),
        ])
    }

    func testTaskThatDoesNotFitGoesToBacklog() {
        let placements = FreeSlotScheduler.fit(
            [SchedulingCandidate(id: "big", duration: 10 * 60, quadrant: .other)],
            busy: [],
            from: t(20)
        )
        XCTAssertEqual(placements, [Placement(id: "big", start: nil)])
    }

    func testPlacedTasksBecomeBusyForTheNextOnes() {
        let placements = FreeSlotScheduler.fit(
            [
                SchedulingCandidate(id: "a", duration: 60, quadrant: .important, order: 0),
                SchedulingCandidate(id: "b", duration: 60, quadrant: .important, order: 1),
            ],
            busy: [],
            from: t(9, 5)
        )
        XCTAssertEqual(placements, [
            Placement(id: "a", start: t(9, 15)),
            Placement(id: "b", start: t(10, 15)),
        ])
    }

    func testStartExactlyAtBusyEndIsAllowed() {
        let placements = FreeSlotScheduler.fit(
            [SchedulingCandidate(id: "a", duration: 30, quadrant: .other)],
            busy: [BusyInterval(start: t(9), end: t(10))],
            from: t(9, 30)
        )
        XCTAssertEqual(placements, [Placement(id: "a", start: t(10))])
    }
}
