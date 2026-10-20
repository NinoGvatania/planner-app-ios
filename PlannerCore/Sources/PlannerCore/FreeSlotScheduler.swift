import Foundation

/// Задача, которую нужно поставить в свободное окно.
public struct SchedulingCandidate: Equatable, Sendable {
    public var id: String
    public var duration: Int
    public var quadrant: Quadrant
    /// Порядок внутри одного квадранта: меньше — раньше (например, смещение дня просроченной задачи).
    public var order: Int

    public init(id: String, duration: Int, quadrant: Quadrant, order: Int = 0) {
        self.id = id
        self.duration = duration
        self.quadrant = quadrant
        self.order = order
    }
}

/// Занятый интервал дня в минутах, `end` не включается.
public struct BusyInterval: Equatable, Sendable {
    public var start: Int
    public var end: Int

    public init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }
}

/// Куда встала задача; `start == nil` — не влезла (уходит в бэклог).
public struct Placement: Equatable, Sendable {
    public var id: String
    public var start: Int?

    public init(id: String, start: Int?) {
        self.id = id
        self.start = start
    }
}

/// «На сегодня — в свободные окна»: важные первыми, с ближайшей четверти часа, что не влезло — в бэклог.
public enum FreeSlotScheduler {
    public static func fit(
        _ candidates: [SchedulingCandidate],
        busy: [BusyInterval],
        from: Int,
        dayEnd: Int = ClockGrid.dayEnd,
        step: Int = ClockGrid.step
    ) -> [Placement] {
        var busy = busy
        let ordered = candidates.sorted { a, b in
            if a.quadrant.rawValue != b.quadrant.rawValue { return a.quadrant.rawValue < b.quadrant.rawValue }
            return a.order < b.order
        }
        var placements: [Placement] = []
        for candidate in ordered {
            var start = roundUp(from, to: step)
            var guardCounter = 0
            while guardCounter < 300,
                  let hit = busy.first(where: { start < $0.end && start + candidate.duration > $0.start }) {
                start = roundUp(hit.end, to: step)
                guardCounter += 1
            }
            if start + candidate.duration > dayEnd {
                placements.append(Placement(id: candidate.id, start: nil))
                continue
            }
            busy.append(BusyInterval(start: start, end: start + candidate.duration))
            placements.append(Placement(id: candidate.id, start: start))
        }
        return placements
    }

    static func roundUp(_ value: Int, to step: Int) -> Int {
        (value + step - 1) / step * step
    }
}
