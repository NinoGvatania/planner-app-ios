import Foundation

/// Задача на сетке дня для раскладки по колонкам.
public struct LayoutItem: Equatable, Sendable {
    public var id: String
    /// Минуты от 0:00.
    public var start: Int
    /// Минуты.
    public var duration: Int

    public init(id: String, start: Int, duration: Int) {
        self.id = id
        self.start = start
        self.duration = duration
    }
}

/// Колонка задачи внутри группы пересекающихся задач.
public struct LanePlacement: Equatable, Sendable {
    public var id: String
    /// Номер колонки, с нуля.
    public var lane: Int
    /// Сколько колонок в группе.
    public var laneCount: Int

    public init(id: String, lane: Int, laneCount: Int) {
        self.id = id
        self.lane = lane
        self.laneCount = laneCount
    }
}

/// Раскладка пересекающихся задач в колонки, как в прототипе: задачи, идущие внахлёст,
/// образуют группу; внутри группы каждая получает колонку, ширина делится поровну.
public enum DayLayout {
    /// Минимальная занимаемая высота в минутах: короткие задачи рисуются не меньше 24 pt,
    /// поэтому две 15‑минутные подряд тоже встают рядом.
    public static let minimumSpan = 26

    public static func lanes(for items: [LayoutItem]) -> [LanePlacement] {
        let sorted = items.sorted { a, b in
            if a.start != b.start { return a.start < b.start }
            return a.duration > b.duration
        }
        var result: [LanePlacement] = []
        var cluster: [Int] = []
        var laneEnds: [Int] = []
        var maxEnd = -1

        func flush() {
            let count = max(1, laneEnds.count)
            for index in cluster {
                result[index].laneCount = count
            }
            cluster = []
            laneEnds = []
        }

        for item in sorted {
            let start = item.start
            let end = start + max(item.duration, minimumSpan)
            if !cluster.isEmpty, start >= maxEnd { flush() }
            if cluster.isEmpty { maxEnd = end }
            var lane = -1
            for (index, laneEnd) in laneEnds.enumerated() where laneEnd <= start {
                lane = index
                break
            }
            if lane == -1 {
                lane = laneEnds.count
                laneEnds.append(end)
            } else {
                laneEnds[lane] = end
            }
            result.append(LanePlacement(id: item.id, lane: lane, laneCount: 1))
            cluster.append(result.count - 1)
            if end > maxEnd { maxEnd = end }
        }
        flush()
        return result
    }
}
