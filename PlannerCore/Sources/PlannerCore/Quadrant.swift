import Foundation

/// Квадрант матрицы Эйзенхауэра. Цвет задачи во всех видах выводится из него.
public enum Quadrant: Int, CaseIterable, Codable, Sendable {
    /// Красный — важно и срочно.
    case urgentImportant = 1
    /// Жёлтый — важно, не срочно.
    case important = 2
    /// Синий — срочно, не важно.
    case urgent = 3
    /// Зелёный — не важно, не срочно. Серый цвет оставлен неразобранным задачам (квадрант не задан).
    case other = 4

    /// Полное название квадранта, как в прототипе.
    public var name: String {
        switch self {
        case .urgentImportant: return "Важно и срочно"
        case .important: return "Важно, не срочно"
        case .urgent: return "Срочно, не важно"
        case .other: return "Не важно, не срочно"
        }
    }

    /// Короткая подпись квадранта в матрице.
    public var label: String {
        switch self {
        case .urgentImportant: return "Сделать сейчас"
        case .important: return "Запланировать"
        case .urgent: return "Быстро закрыть"
        case .other: return "Когда-нибудь"
        }
    }

    /// Квадрант по признакам «важно» и «срочно».
    public init(important: Bool, urgent: Bool) {
        switch (important, urgent) {
        case (true, true): self = .urgentImportant
        case (true, false): self = .important
        case (false, true): self = .urgent
        case (false, false): self = .other
        }
    }
}
