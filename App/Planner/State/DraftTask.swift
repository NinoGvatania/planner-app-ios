import Foundation
import PlannerCore

/// Задача, распознанная из диктовки, но ещё не сохранённая: её можно поправить или удалить.
struct DraftTask: Identifiable, Equatable {
    let id: UUID
    var title: String
    var dayOffset: Int?
    var start: Int?
    var duration: Int
    /// 0 — не разобрано.
    var quadrantRaw: Int
    var project: String

    init(parsed: ParsedTask, id: UUID = UUID()) {
        self.id = id
        title = parsed.title
        dayOffset = parsed.dayOffset
        start = parsed.start
        duration = parsed.duration
        quadrantRaw = parsed.quadrant?.rawValue ?? 0
        project = parsed.project ?? ""
    }

    /// Разобрать надиктованный текст на черновики задач.
    static func drafts(from text: String) -> [DraftTask] {
        let parser = QuickAddParser()
        return DictationSplitter.split(text).compactMap { piece in
            guard case .task(let parsed) = parser.parse(piece), !parsed.title.isEmpty else { return nil }
            return DraftTask(parsed: parsed)
        }
    }

    var whenText: String {
        guard let offset = dayOffset else { return "бэклог" }
        let label = DayMath.label(offset: offset)
        guard let start = start else { return label + " · весь день" }
        return label + " · " + ClockGrid.format(minutes: start) + "–" + ClockGrid.format(minutes: start + duration)
    }
}
