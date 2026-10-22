import Foundation
import FoundationModels
import PlannerCore

/// Разбор расшифровки диктовки на задачи. По порядку:
/// 1. Claude по своему ключу API, если он задан и включён в настройках (текст уходит на api.anthropic.com);
/// 2. Apple Intelligence на устройстве (FoundationModels) — пробуется всегда, но русский модель Apple
///    официально не поддерживает, и iOS обычно отказывает;
/// 3. правила: `DictationSplitter` с частями речи от NaturalLanguage, `SpeechCleanup` и парсер быстрого ввода.
/// Почему не сработали модели, видно на экране разбора.
enum TaskExtractor {
    enum Source: Equatable {
        /// Claude, модель `model`.
        case claude(model: String)
        /// Apple Intelligence на устройстве; `reason` — почему не Claude (если пробовали).
        case apple(reason: String?)
        /// Правила; `reason` — почему не модель.
        case rules(reason: String?)
    }

    /// Разобрать текст. Возвращает задачи и чем разбирали.
    /// `vocabulary` — проекты и недавние задачи пользователя: по ним модель правит искажённые названия.
    static func extract(_ transcript: String, vocabulary: DictationVocabulary = DictationVocabulary()) async -> (drafts: [DraftTask], source: Source) {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return ([], .rules(reason: nil)) }
        var reasons: [String] = []
        if ClaudeSettings.isEnabled {
            let model = ClaudeSettings.model
            do {
                let drafts = dedupe(try await ClaudeExtractor.extract(text, apiKey: ClaudeSettings.apiKey, model: model, vocabulary: vocabulary))
                if !drafts.isEmpty { return (drafts, .claude(model: model)) }
                reasons.append("Claude не нашёл задач")
            } catch {
                reasons.append(ClaudeExtractor.message(for: error))
            }
        }
        // Apple Intelligence пробуем всегда, что бы ни говорила проверка доступности: если системе что-то
        // не нравится, она сама откажет, и причина будет видна на экране.
        let status = OnDeviceExtractor.status
        do {
            let drafts = dedupe(try await OnDeviceExtractor.extract(text))
            if !drafts.isEmpty { return (drafts, .apple(reason: reasons.isEmpty ? nil : reasons.joined(separator: ". "))) }
            reasons.append("Apple Intelligence не нашёл задач")
        } catch {
            reasons.append(OnDeviceExtractor.message(for: error, status: status))
        }
        return (byRules(text), .rules(reason: reasons.joined(separator: ". ") + ". Разобрано правилами"))
    }

    /// Задача из ответа модели (Claude или Apple): пустая строка и 0 — «не сказано».
    static func draft(title rawTitle: String, day: String, start rawStart: String, durationMinutes: Int,
                      important: Int, urgent: Int, project rawProject: String, note: String = "") -> DraftTask? {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard SpeechCleanup.isMeaningful(title) else { return nil }
        var dayOffset: Int?
        let dayText = day.trimmingCharacters(in: .whitespacesAndNewlines)
        if !dayText.isEmpty {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = DayMath.calendar
            formatter.timeZone = DayMath.calendar.timeZone
            formatter.dateFormat = "yyyy-MM-dd"
            if let date = formatter.date(from: dayText) {
                dayOffset = DayMath.offset(of: date)
            }
        }
        var start: Int?
        let parts = rawStart.split(separator: ":").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
        if parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) {
            start = ClockGrid.snapped(parts[0] * 60 + parts[1])
        }
        if start != nil, dayOffset == nil { dayOffset = 0 }
        var duration = max(15, min(8 * 60, ClockGrid.snapped(durationMinutes > 0 ? durationMinutes : 30)))
        if let start { duration = max(15, min(duration, ClockGrid.dayEnd - start)) }
        var quadrant: Quadrant?
        if important != 0 || urgent != 0 {
            quadrant = Quadrant(important: important > 0, urgent: urgent > 0)
        }
        let project = rawProject.trimmingCharacters(in: .whitespacesAndNewlines)
        let parsed = ParsedTask(
            title: SpeechCleanup.capitalized(title),
            dayOffset: dayOffset,
            start: start,
            duration: duration,
            quadrant: quadrant,
            project: project.isEmpty ? nil : project
        )
        var draft = DraftTask(parsed: parsed)
        draft.notes = note.trimmingCharacters(in: .whitespacesAndNewlines)
        return draft
    }

    /// Одинаковые задачи (то же название, день и время) оставляем по одной; разные заметки повторов
    /// не теряются — дописываются к оставленной.
    static func dedupe(_ drafts: [DraftTask]) -> [DraftTask] {
        var result: [DraftTask] = []
        var index: [String: Int] = [:]
        for draft in drafts {
            let key = draft.title.lowercased() + "|\(draft.dayOffset ?? -999)|\(draft.start ?? -1)"
            guard let kept = index[key] else {
                index[key] = result.count
                result.append(draft)
                continue
            }
            let note = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            if !note.isEmpty, !result[kept].notes.contains(note) {
                result[kept].notes = result[kept].notes.isEmpty ? note : result[kept].notes + "\n" + note
            }
        }
        return result
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
            case .available: return "Apple Intelligence на устройстве включён, но русский язык моделью Apple официально не поддерживается — iOS обычно отказывает"
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
            case .deviceNotEligible: return .unavailable("Apple Intelligence: этот iPhone его не поддерживает")
            case .appleIntelligenceNotEnabled: return .unavailable("Apple Intelligence выключен в Настройках iOS → Apple Intelligence и Siri")
            case .modelNotReady: return .unavailable("Apple Intelligence: модель ещё загружается")
            @unknown default: return .unavailable("Apple Intelligence недоступен")
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
        @Guide(description: "Важные подробности задачи: что именно, кому, сколько, список, срок вроде «до обеда»; иначе пустая строка")
        var note: String
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
        write task titles in Russian, exactly as a native speaker would. Never refuse, never apologise,
        never switch to English in the output, never translate names. Russian input is expected and fine.

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
        - start: 24-hour HH:MM when a time is said: «в 10» → 10:00, «в час дня» → 13:00, «в 12 ночи» → 00:00;
          a bare hour from 1 to 6 means afternoon («в 3» → 15:00, «в половине третьего» → 14:30);
          «утром/днём/вечером/ночью» without a number → 09:00/14:00/19:00/23:00, with a number they pick the
          half of the day («вечером в 7» → 19:00); otherwise empty.
        - durationMinutes: only when said («на час» → 60); otherwise 0.
        - important / urgent: 1 only when the user explicitly says «важно» / «срочно», -1 for «не важно» /
          «не срочно», otherwise 0.
        - project: the name after «по проекту …» or «#…»; otherwise empty.
        - note: important details in Russian (what exactly, to whom, how many, a list, a deadline such as
          «до обеда»); otherwise empty. The title keeps only the essence.
        Answer only with the structured result.
        """
    }

    static func extract(_ transcript: String) async throws -> [DraftTask] {
        let session = LanguageModelSession(instructions: instructions(today: Date()))
        let response = try await session.respond(to: "Расшифровка:\n\(transcript)", generating: TaskList.self)
        return response.content.tasks.compactMap { task in
            TaskExtractor.draft(
                title: task.title, day: task.day, start: task.start, durationMinutes: task.durationMinutes,
                important: task.important, urgent: task.urgent, project: task.project, note: task.note
            )
        }
    }

    /// Честно: что именно ответила система, чтобы было понятно, почему разбирали правилами.
    static func message(for error: Error, status: Status) -> String {
        // Система заранее сказала, почему модели нет, — это понятнее общего текста ошибки.
        if case .unavailable(let reason) = status { return reason }
        if let generation = error as? LanguageModelSession.GenerationError {
            switch generation {
            case .unsupportedLanguageOrLocale:
                return "Apple Intelligence: iOS отказал — русский язык моделью Apple не поддерживается"
            case .exceededContextWindowSize: return "Apple Intelligence: диктовка слишком длинная"
            case .guardrailViolation: return "Apple Intelligence отказался от этого текста (фильтр)"
            default: return "Apple Intelligence: \(generation.localizedDescription)"
            }
        }
        return "Apple Intelligence: \(error.localizedDescription)"
    }
}
