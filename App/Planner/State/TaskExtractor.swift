import Foundation
import FoundationModels
import PlannerCore

/// Разбор расшифровки диктовки на задачи — целиком на устройстве, без сети.
/// Если доступен Apple Intelligence (FoundationModels) и он понимает русский — модель делит текст по смыслу
/// и чистит формулировки; иначе правила: `DictationSplitter` с частями речи от NaturalLanguage,
/// `SpeechCleanup` и парсер быстрого ввода.
enum TaskExtractor {
    enum Source: Equatable {
        case model
        /// Правила; `reason` — почему не модель (nil — модель на этом iPhone недоступна, это обычный режим).
        case rules(reason: String?)
    }

    /// Разобрать текст. Возвращает задачи и чем разбирали.
    static func extract(_ transcript: String) async -> (drafts: [DraftTask], source: Source) {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return ([], .rules(reason: nil)) }
        guard case .available = OnDeviceExtractor.status else { return (byRules(text), .rules(reason: nil)) }
        do {
            let raw = try await OnDeviceExtractor.extract(text)
            let drafts = dedupe(raw)
            guard !drafts.isEmpty else { return (byRules(text), .rules(reason: "Apple Intelligence не нашёл задач — разобрано правилами")) }
            return (drafts, .model)
        } catch {
            return (byRules(text), .rules(reason: OnDeviceExtractor.message(for: error)))
        }
    }

    /// Одинаковые задачи (то же название, день и время) оставляем по одной.
    static func dedupe(_ drafts: [DraftTask]) -> [DraftTask] {
        var seen = Set<String>()
        return drafts.filter { draft in
            let key = draft.title.lowercased() + "|\(draft.dayOffset ?? -999)|\(draft.start ?? -1)"
            return seen.insert(key).inserted
        }
    }

    /// Правила: деление на куски, чистка мусора, парсер быстрого ввода для дня, времени и квадранта.
    static func byRules(_ text: String) -> [DraftTask] {
        let parser = QuickAddParser()
        let drafts = DictationSplitter.split(text, linguistics: AppleLinguistics.shared).compactMap { piece -> DraftTask? in
            let cleaned = SpeechCleanup.clean(piece)
            guard SpeechCleanup.isMeaningful(cleaned) else { return nil }
            let parsed = parser.parseTask(cleaned)
            guard !parsed.title.isEmpty, parsed.title != "Новая задача" else { return nil }
            var draft = DraftTask(parsed: parsed)
            draft.title = SpeechCleanup.tidyTitle(draft.title)
            return draft
        }
        return dedupe(drafts)
    }
}

/// Apple Intelligence на устройстве: системная языковая модель с ответом строго по структуре.
enum OnDeviceExtractor {
    enum Status: Equatable {
        case available
        case unavailable(String)

        var note: String {
            switch self {
            case .available: return "Apple Intelligence на устройстве — доступен"
            case .unavailable(let reason): return reason
            }
        }
    }

    /// Модель пробуем всегда, когда она есть: официальный список языков не проверяем, по-русски
    /// просим в инструкции; если система всё же откажет, разберём правилами.
    static var status: Status {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return .available
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible: return .unavailable("Этот iPhone не поддерживает Apple Intelligence — разбор правилами")
            case .appleIntelligenceNotEnabled: return .unavailable("Apple Intelligence выключен в Настройках iOS — разбор правилами")
            case .modelNotReady: return .unavailable("Модель Apple Intelligence ещё загружается — разбор правилами")
            @unknown default: return .unavailable("Apple Intelligence недоступен — разбор правилами")
            }
        }
    }

    @Generable
    struct TaskList {
        @Guide(description: "Отдельные задачи из расшифровки: одна задача — одно действие")
        var tasks: [ExtractedTask]
    }

    @Generable
    struct ExtractedTask {
        @Guide(description: "Короткое название в неопределённой форме, без речевого мусора и без точки в конце, например «Позвонить маме»")
        var title: String
        @Guide(description: "День в формате YYYY-MM-DD, если он назван (сегодня, завтра, день недели, дата); иначе пустая строка")
        var day: String
        @Guide(description: "Время начала в формате HH:MM (24 часа), если названо; иначе пустая строка")
        var start: String
        @Guide(description: "Длительность в минутах, если названа; иначе 0")
        var durationMinutes: Int
        @Guide(description: "1 — прямо сказано «важно», -1 — «не важно», 0 — не сказано")
        var important: Int
        @Guide(description: "1 — прямо сказано «срочно», -1 — «не срочно», 0 — не сказано")
        var urgent: Int
        @Guide(description: "Название проекта, если сказано «по проекту …» или «#…»; иначе пустая строка")
        var project: String
    }

    /// Инструкция по-английски (так модель слушается лучше), с требованием работать на любом языке
    /// ввода и отвечать на языке пользователя — по-русски.
    static func instructions(today: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "EEEE, d MMMM yyyy"
        let iso = DateFormatter()
        iso.dateFormat = "yyyy-MM-dd"
        return """
        You are a multilingual assistant built into a personal task planner. You work in every language,
        including Russian: the user dictates in Russian, you understand Russian perfectly and you always
        write task titles in Russian, exactly as a native speaker would. Never refuse or switch languages.

        Today is \(formatter.string(from: today)) (\(iso.string(from: today))). The week starts on Monday.

        Your job: turn a raw speech-to-text transcript into a list of separate tasks.
        - Split by meaning: one task = one action. Do not split a single thought into pieces and do not
          merge different actions into one task.
        - Remove speech fillers, repetitions, self-corrections and lead-ins
          («ну», «короче», «мне нужно», «как бы», «это самое», «значит»).
        - Title: short, clear, infinitive verb first («Позвонить маме», «Купить запчасти»), no trailing period,
          keep names and numbers exactly as said.
        - Never invent tasks. Skip phrases that are not tasks (comments, interjections).
        - day: resolve «сегодня», «завтра», «послезавтра», weekday names (the nearest future one) and dates
          to YYYY-MM-DD; otherwise empty string.
        - start: 24-hour HH:MM when a time is said («в 10», «в половине третьего» → 14:30); otherwise empty.
        - durationMinutes: only when said («на час» → 60); otherwise 0.
        - important / urgent: 1 only when the user explicitly says «важно» / «срочно», -1 for «не важно» /
          «не срочно», otherwise 0.
        - project: the name after «по проекту …» or «#…»; otherwise empty.
        Answer only with the structured result.
        """
    }

    static func extract(_ transcript: String) async throws -> [DraftTask] {
        let session = LanguageModelSession(instructions: instructions(today: Date()))
        let response = try await session.respond(to: "Расшифровка:\n\(transcript)", generating: TaskList.self)
        return response.content.tasks.compactMap(draft(from:))
    }

    static func message(for error: Error) -> String {
        if let generation = error as? LanguageModelSession.GenerationError {
            switch generation {
            case .unsupportedLanguageOrLocale: return "Apple Intelligence не понимает этот язык — разобрано правилами"
            case .exceededContextWindowSize: return "Диктовка слишком длинная для Apple Intelligence — разобрано правилами"
            case .guardrailViolation: return "Apple Intelligence отказался разбирать этот текст — разобрано правилами"
            default: return "Apple Intelligence не справился — разобрано правилами"
            }
        }
        return "Apple Intelligence не справился — разобрано правилами"
    }

    private static func draft(from task: ExtractedTask) -> DraftTask? {
        let title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard SpeechCleanup.isMeaningful(title) else { return nil }
        var dayOffset: Int?
        if !task.day.isEmpty {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = DayMath.calendar.timeZone
            if let date = formatter.date(from: task.day) {
                dayOffset = DayMath.offset(of: date)
            }
        }
        var start: Int?
        let parts = task.start.split(separator: ":").compactMap { Int($0) }
        if parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) {
            start = ClockGrid.snapped(parts[0] * 60 + parts[1])
        }
        if start != nil, dayOffset == nil { dayOffset = 0 }
        var duration = max(15, min(8 * 60, ClockGrid.snapped(task.durationMinutes > 0 ? task.durationMinutes : 30)))
        if let start { duration = max(15, min(duration, ClockGrid.dayEnd - start)) }
        var quadrant: Quadrant?
        if task.important != 0 || task.urgent != 0 {
            quadrant = Quadrant(important: task.important > 0, urgent: task.urgent > 0)
        }
        let project = task.project.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = ParsedTask(
            title: SpeechCleanup.capitalized(title),
            dayOffset: dayOffset,
            start: start,
            duration: duration,
            quadrant: quadrant,
            project: project.isEmpty ? nil : project
        )
        return DraftTask(parsed: parsed)
    }
}
