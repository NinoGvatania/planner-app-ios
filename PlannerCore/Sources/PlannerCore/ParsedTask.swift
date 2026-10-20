import Foundation

/// Результат разбора строки быстрого ввода.
public struct ParsedTask: Equatable, Sendable {
    /// Название без служебных слов, с заглавной буквы.
    public var title: String
    /// Смещение дня от сегодняшнего: 0 — сегодня, 1 — завтра; `nil` — в бэклог.
    public var dayOffset: Int?
    /// Начало в минутах от 0:00; `nil` — весь день или без времени.
    public var start: Int?
    /// Длительность в минутах.
    public var duration: Int
    /// Квадрант, если пользователь его назвал; `nil` — задача не разобрана (серая).
    public var quadrant: Quadrant?
    /// Проект из `#метки`.
    public var project: String?

    public init(title: String, dayOffset: Int?, start: Int?, duration: Int = 30, quadrant: Quadrant? = nil, project: String? = nil) {
        self.title = title
        self.dayOffset = dayOffset
        self.start = start
        self.duration = duration
        self.quadrant = quadrant
        self.project = project
    }
}

/// Что сказал пользователь: новая задача или команда.
public enum QuickAddCommand: Equatable, Sendable {
    case task(ParsedTask)
    /// «Что у меня завтра?»
    case agenda(dayOffset: Int)
    /// «Перенеси просроченные на сегодня / завтра».
    case fitOverdue(dayOffset: Int)
}
