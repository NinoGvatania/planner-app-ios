import Foundation
import PlannerCore
import SwiftData

/// Шаблон ежедневной рутины; на каждый день порождает `PlannerTask` с `isRoutine = true`.
@Model
final class Routine {
    var title: String
    /// Минуты от 0:00.
    var start: Int
    var duration: Int
    var quadrantRaw: Int
    /// Дни недели, 1 — воскресенье … 7 — суббота (как `Calendar.weekday`). Пусто — каждый день.
    var weekdays: [Int]

    init(title: String, start: Int, duration: Int = 30, quadrant: Quadrant = .urgent, weekdays: [Int] = []) {
        self.title = title
        self.start = start
        self.duration = duration
        self.quadrantRaw = quadrant.rawValue
        self.weekdays = weekdays
    }

    var quadrant: Quadrant {
        get { Quadrant(rawValue: quadrantRaw) ?? .other }
        set { quadrantRaw = newValue.rawValue }
    }
}
