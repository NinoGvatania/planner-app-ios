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
    /// По какой день включительно копии уже созданы: удалённые или перенесённые копии не возвращаются.
    var materializedThrough: Date? = nil
    /// Проект копий (по имени, чтобы не заводить вторую связь с `Project`).
    var projectName: String? = nil

    init(title: String, start: Int, duration: Int = 30, quadrant: Quadrant = .urgent, weekdays: [Int] = [], projectName: String? = nil) {
        self.title = title
        self.start = start
        self.duration = duration
        self.quadrantRaw = quadrant.rawValue
        self.weekdays = weekdays
        self.projectName = projectName
    }

    var quadrant: Quadrant {
        get { Quadrant(rawValue: quadrantRaw) ?? .other }
        set { quadrantRaw = newValue.rawValue }
    }
}
