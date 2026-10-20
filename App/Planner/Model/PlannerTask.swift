import Foundation
import PlannerCore
import SwiftData

/// Задача. Название — обязательное, всё остальное опционально (см. docs/PLAN.md).
@Model
final class PlannerTask {
    @Attribute(.unique) var id: UUID
    var title: String
    /// Начало календарного дня; `nil` — задача в бэклоге.
    var day: Date?
    /// Минуты от 0:00; `nil` — «весь день».
    var start: Int?
    /// Длительность в минутах, шаг 15.
    var duration: Int
    /// Квадрант Эйзенхауэра, см. `Quadrant`; 0 — не разобрана (серая).
    var quadrantRaw: Int
    var isDone: Bool
    /// Ежедневная рутина: никогда не считается просроченной.
    var isRoutine: Bool
    var project: Project?
    /// Больше — выше в бэклоге; растёт при каждом возврате задачи в бэклог.
    var backlogRank: Int
    var createdAt: Date
    var completedAt: Date?

    init(
        title: String,
        day: Date?,
        start: Int?,
        duration: Int = 30,
        quadrant: Quadrant? = nil,
        isDone: Bool = false,
        isRoutine: Bool = false,
        project: Project? = nil,
        backlogRank: Int = 0
    ) {
        self.id = UUID()
        self.title = title
        self.day = day
        self.start = start
        self.duration = duration
        self.quadrantRaw = quadrant?.rawValue ?? 0
        self.isDone = isDone
        self.isRoutine = isRoutine
        self.project = project
        self.backlogRank = backlogRank
        self.createdAt = Date()
        self.completedAt = isDone ? Date() : nil
    }

    /// Квадрант для раскладки и сортировки; неразобранная задача считается «не важно, не срочно».
    var quadrant: Quadrant {
        get { Quadrant(rawValue: quadrantRaw) ?? .other }
        set { quadrantRaw = newValue.rawValue }
    }

    /// Квадрант, если задача разобрана.
    var sortedQuadrant: Quadrant? { Quadrant(rawValue: quadrantRaw) }
    var isSorted: Bool { sortedQuadrant != nil }

    var isInBacklog: Bool { day == nil }

    var end: Int? {
        guard let start = start else { return nil }
        return start + duration
    }

    /// Просрочена: день прошёл, не сделана, не рутина.
    func isOverdue(today: Date) -> Bool {
        guard let day = day else { return false }
        return day < today && !isDone && !isRoutine
    }
}
