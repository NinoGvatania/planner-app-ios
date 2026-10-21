import Foundation
import PlannerCore

/// Разбор расшифровки диктовки на задачи. С ключом Claude API — модель делит по смыслу и чистит
/// формулировки; без ключа или без сети — правила (`DictationSplitter` + `SpeechCleanup` + парсер).
enum TaskExtractor {
    enum Source: Equatable {
        case model
        /// Правила; `reason` — почему не модель (nil — ключа нет, это нормальный режим).
        case rules(reason: String?)
    }

    static let apiKeyAccount = "anthropicAPIKey"
    static let modelKey = "extractorModel"
    static let defaultModel = "claude-haiku-5-5"
    static let models: [(id: String, title: String)] = [
        ("claude-haiku-5-5", "Haiku 5.5 — быстро и дёшево"),
        ("claude-sonnet-5-5", "Sonnet 5.5 — точнее"),
        ("claude-opus-5-5", "Opus 5.5 — самый точный"),
    ]

    static var apiKey: String { KeychainStore.read(apiKeyAccount) ?? "" }
    static var hasKey: Bool { !apiKey.isEmpty }
    static var model: String { UserDefaults.standard.string(forKey: modelKey) ?? defaultModel }

    /// Разобрать текст. Возвращает задачи и чем разбирали.
    static func extract(_ transcript: String) async -> (drafts: [DraftTask], source: Source) {
        let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return ([], .rules(reason: nil)) }
        guard hasKey else { return (byRules(text), .rules(reason: nil)) }
        do {
            let drafts = try await ClaudeExtractor.extract(text, apiKey: apiKey, model: model)
            guard !drafts.isEmpty else { return (byRules(text), .rules(reason: "Модель не нашла задач — разобрано правилами")) }
            return (drafts, .model)
        } catch let error as ClaudeExtractor.ExtractError {
            return (byRules(text), .rules(reason: error.userMessage))
        } catch let error as URLError {
            let offline = error.code == .notConnectedToInternet || error.code == .networkConnectionLost || error.code == .cannotFindHost
            return (byRules(text), .rules(reason: offline ? "Нет сети — разобрано правилами" : "Сеть не ответила — разобрано правилами"))
        } catch {
            return (byRules(text), .rules(reason: "Модель недоступна — разобрано правилами"))
        }
    }

    /// Правила: деление на куски, чистка мусора, парсер быстрого ввода для дня, времени и квадранта.
    static func byRules(_ text: String) -> [DraftTask] {
        let parser = QuickAddParser()
        return DictationSplitter.split(text).compactMap { piece in
            let cleaned = SpeechCleanup.clean(piece)
            guard SpeechCleanup.isMeaningful(cleaned) else { return nil }
            let parsed = parser.parseTask(cleaned)
            guard !parsed.title.isEmpty, parsed.title != "Новая задача" else { return nil }
            return DraftTask(parsed: parsed)
        }
    }
}

/// Вызов Claude API (Messages) со структурированным ответом по схеме.
enum ClaudeExtractor {
    struct ExtractedTask: Decodable {
        let title: String
        let day: String?
        let start: String?
        let durationMinutes: Int?
        let important: Bool?
        let urgent: Bool?
        let project: String?

        enum CodingKeys: String, CodingKey {
            case title, day, start, important, urgent, project
            case durationMinutes = "duration_minutes"
        }
    }

    struct Payload: Decodable { let tasks: [ExtractedTask] }

    enum ExtractError: Error {
        case badResponse, refusal, truncated
        case http(Int)

        /// Что сказать пользователю, почему разбирали правилами.
        var userMessage: String {
            switch self {
            case .http(401), .http(403): return "Ключ Claude API не принят — проверь его в настройках; разобрано правилами"
            case .http(429): return "Лимит Claude API исчерпан — разобрано правилами"
            case .http(let code): return "Claude API: ошибка \(code) — разобрано правилами"
            case .refusal: return "Модель отказалась разбирать этот текст — разобрано правилами"
            case .truncated: return "Диктовка слишком длинная для одного ответа модели — разобрано правилами"
            case .badResponse: return "Непонятный ответ модели — разобрано правилами"
            }
        }
    }

    static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "tasks": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string"],
                        "day": ["type": ["string", "null"]],
                        "start": ["type": ["string", "null"]],
                        "duration_minutes": ["type": ["integer", "null"]],
                        "important": ["type": ["boolean", "null"]],
                        "urgent": ["type": ["boolean", "null"]],
                        "project": ["type": ["string", "null"]],
                    ],
                    "required": ["title", "day", "start", "duration_minutes", "important", "urgent", "project"],
                    "additionalProperties": false,
                ],
            ],
        ],
        "required": ["tasks"],
        "additionalProperties": false,
    ]

    static func systemPrompt(today: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "EEEE, d MMMM yyyy"
        let iso = DateFormatter()
        iso.dateFormat = "yyyy-MM-dd"
        return """
        Ты разбираешь расшифровку голосовой диктовки на отдельные задачи для личного планировщика.
        Сегодня \(formatter.string(from: today)) (\(iso.string(from: today))).
        Правила:
        - Дели текст по смыслу: одна задача — одно действие. Не дроби одну мысль на куски и не склеивай разные.
        - Убирай речевой мусор, повторы, оговорки и вводные слова («ну», «короче», «мне нужно», «как бы»).
        - Название — короткое, понятное, в неопределённой форме («Позвонить маме», «Купить запчасти»), без точки в конце.
        - Ничего не выдумывай: только то, что сказано. Если фраза не задача (комментарий, междометие), пропусти её.
        - day: "YYYY-MM-DD", если назван день (сегодня, завтра, послезавтра, день недели — ближайший будущий, дата); иначе null.
        - start: "HH:MM" в 24-часовом формате, если названо время; иначе null. duration_minutes: если названа длительность; иначе null.
        - important / urgent: true или false только если сказано прямо («важно», «срочно», «не срочно»); иначе null.
        - project: название проекта, если сказано «по проекту …» или «#…»; иначе null.
        Отвечай только JSON по схеме.
        """
    }

    static func extract(_ transcript: String, apiKey: String, model: String) async throws -> [DraftTask] {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 40
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            "system": systemPrompt(today: Date()),
            "messages": [["role": "user", "content": "Расшифровка:\n\(transcript)"]],
            "output_config": ["format": ["type": "json_schema", "schema": schema]],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ExtractError.badResponse }
        guard (200..<300).contains(http.statusCode) else { throw ExtractError.http(http.statusCode) }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ExtractError.badResponse }
        if json["stop_reason"] as? String == "refusal" { throw ExtractError.refusal }
        if json["stop_reason"] as? String == "max_tokens" { throw ExtractError.truncated }
        guard let content = json["content"] as? [[String: Any]],
              let text = content.first(where: { $0["type"] as? String == "text" })?["text"] as? String,
              let payloadData = text.data(using: .utf8) else { throw ExtractError.badResponse }
        let payload = try JSONDecoder().decode(Payload.self, from: payloadData)
        return payload.tasks.compactMap(draft(from:))
    }

    private static func draft(from task: ExtractedTask) -> DraftTask? {
        let title = task.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard SpeechCleanup.isMeaningful(title) else { return nil }
        var dayOffset: Int?
        if let day = task.day {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd"
            formatter.timeZone = DayMath.calendar.timeZone
            if let date = formatter.date(from: day) {
                dayOffset = DayMath.offset(of: date)
            }
        }
        var start: Int?
        if let time = task.start {
            let parts = time.split(separator: ":").compactMap { Int($0) }
            if parts.count == 2, (0..<24).contains(parts[0]), (0..<60).contains(parts[1]) {
                start = ClockGrid.snapped(parts[0] * 60 + parts[1])
            }
        }
        if start != nil, dayOffset == nil { dayOffset = 0 }
        let duration = max(15, min(8 * 60, ClockGrid.snapped(task.durationMinutes ?? 30)))
        var quadrant: Quadrant?
        if task.important != nil || task.urgent != nil {
            quadrant = Quadrant(important: task.important ?? false, urgent: task.urgent ?? false)
        }
        let parsed = ParsedTask(
            title: SpeechCleanup.capitalized(title),
            dayOffset: dayOffset,
            start: start,
            duration: duration,
            quadrant: quadrant,
            project: task.project?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        )
        return DraftTask(parsed: parsed)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
