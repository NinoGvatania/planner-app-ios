import Foundation
import PlannerCore

/// Настройки разбора диктовки через Claude: свой ключ API (в связке ключей iPhone), модель, вкл/выкл.
enum ClaudeSettings {
    static let keyAccount = "anthropicAPIKey"
    static let enabledKey = "claudeEnabled"
    static let modelKey = "claudeModel"
    static let defaultModel = "claude-opus-5-5"
    static let models: [(id: String, title: String)] = [
        ("claude-opus-5-5", "Opus 5.5 — точнее всех"),
        ("claude-sonnet-5-5", "Sonnet 5.5 — быстрее"),
        ("claude-haiku-5-5", "Haiku 5.5 — самый быстрый и дешёвый"),
    ]

    static var apiKey: String { KeychainStore.read(keyAccount) ?? "" }
    static var hasKey: Bool { !apiKey.isEmpty }
    /// Включён, пока есть ключ и переключатель в настройках не выключен.
    static var isEnabled: Bool {
        hasKey && (UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true)
    }
    static var model: String { UserDefaults.standard.string(forKey: modelKey) ?? defaultModel }

    static func title(of model: String) -> String {
        models.first { $0.id == model }.map { String($0.title.split(separator: " ").prefix(2).joined(separator: " ")) } ?? model
    }
}

/// Разбор расшифровки через Claude API (Messages) со структурированным ответом строго по JSON‑схеме.
/// Текст диктовки уходит только на api.anthropic.com с ключом пользователя.
enum ClaudeExtractor {
    enum ExtractError: Error {
        case noKey
        case http(Int, String?)
        case refusal
        case truncated
        case badResponse
    }

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!
    private static let version = "2023-06-01"

    /// Ответ по схеме: те же поля, что у разбора на устройстве. Пустая строка и 0 — «не сказано».
    private struct Payload: Decodable {
        let tasks: [Item]
    }

    private struct Item: Decodable {
        let title: String
        let day: String
        let start: String
        let durationMinutes: Int
        let important: Int
        let urgent: Int
        let project: String
    }

    /// Схема для `output_config.format`: у каждого объекта `additionalProperties: false`, все поля обязательны.
    static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "tasks": [
                "type": "array",
                "items": [
                    "type": "object",
                    "properties": [
                        "title": ["type": "string", "description": "Короткое название задачи по-русски, глагол в неопределённой форме"],
                        "day": ["type": "string", "description": "YYYY-MM-DD или пустая строка"],
                        "start": ["type": "string", "description": "HH:MM (24 часа) или пустая строка"],
                        "durationMinutes": ["type": "integer", "description": "Длительность в минутах или 0"],
                        "important": ["type": "integer", "enum": [-1, 0, 1]],
                        "urgent": ["type": "integer", "enum": [-1, 0, 1]],
                        "project": ["type": "string", "description": "Название проекта или пустая строка"],
                    ],
                    "required": ["title", "day", "start", "durationMinutes", "important", "urgent", "project"],
                    "additionalProperties": false,
                ],
            ],
        ],
        "required": ["tasks"],
        "additionalProperties": false,
    ]

    /// Инструкция с сегодняшней датой и ближайшими днями недели — чтобы «в пятницу» превращалось в точную дату.
    static func systemPrompt(today: Date) -> String {
        let calendar = DayMath.calendar
        let long = DateFormatter()
        long.locale = Locale(identifier: "ru_RU")
        long.calendar = calendar
        long.timeZone = calendar.timeZone
        long.dateFormat = "EEEE, d MMMM yyyy"
        let iso = DateFormatter()
        iso.calendar = calendar
        iso.timeZone = calendar.timeZone
        iso.locale = Locale(identifier: "en_US_POSIX")
        iso.dateFormat = "yyyy-MM-dd"
        let weekday = DateFormatter()
        weekday.locale = Locale(identifier: "ru_RU")
        weekday.calendar = calendar
        weekday.timeZone = calendar.timeZone
        weekday.dateFormat = "EEEE"
        let start = calendar.startOfDay(for: today)
        let nextDays = (1...7).compactMap { offset -> String? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return "\(weekday.string(from: date)) — \(iso.string(from: date))"
        }.joined(separator: ", ")
        return """
        Ты разбираешь расшифровку голосовой диктовки на отдельные задачи для личного планировщика. \
        Пользователь говорит по-русски, названия задач пиши по-русски.

        Сегодня \(long.string(from: today)) (\(iso.string(from: today))). Ближайшие дни: \(nextDays). \
        Неделя начинается с понедельника.

        Правила:
        - Дели текст по смыслу: одна задача — одно действие. Не дроби одну мысль на куски и не склеивай разные действия.
        - Убирай речевой мусор, повторы, оговорки и вводные слова («ну», «короче», «мне нужно», «надо», «как бы», \
        «это самое», «значит», «запиши»). Если человек поправил себя, оставь исправленный вариант.
        - title: короткое понятное название, глагол в неопределённой форме первым («Позвонить маме», \
        «Купить запчасти»), без точки в конце. Имена, числа и названия — как сказаны.
        - Ничего не выдумывай: только то, что сказано. Фразы, которые не задачи (комментарии, приветствия, \
        междометия), пропускай.
        - day: «сегодня», «завтра», «послезавтра», день недели (ближайший будущий) и даты переводи в YYYY-MM-DD \
        по списку выше; если день не назван — пустая строка.
        - start: время начала «HH:MM» в 24-часовом формате («в 10» → 10:00, «в половине третьего дня» → 14:30, \
        «в семь вечера» → 19:00); если не названо — пустая строка.
        - durationMinutes: только если длительность названа («на час» → 60, «минут на сорок» → 40); иначе 0.
        - important / urgent: 1 только если прямо сказано «важно» / «срочно», -1 — «не важно» / «не срочно», иначе 0.
        - project: название после «по проекту …» или «#…»; иначе пустая строка.
        """
    }

    /// Разобрать текст. Бросает `ExtractError` или `URLError`.
    static func extract(_ transcript: String, apiKey: String, model: String) async throws -> [DraftTask] {
        guard !apiKey.isEmpty else { throw ExtractError.noKey }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(version, forHTTPHeaderField: "anthropic-version")
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
        guard (200..<300).contains(http.statusCode) else {
            throw ExtractError.http(http.statusCode, errorMessage(in: data))
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ExtractError.badResponse }
        // Отказ и обрезанный ответ проверяем до разбора: в них JSON может не соответствовать схеме.
        switch json["stop_reason"] as? String {
        case "refusal": throw ExtractError.refusal
        case "max_tokens": throw ExtractError.truncated
        default: break
        }
        // Ответ по схеме — в текстовом блоке (блоки размышлений пропускаем).
        guard let content = json["content"] as? [[String: Any]],
              let text = content.last(where: { $0["type"] as? String == "text" })?["text"] as? String,
              let payloadData = text.data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: payloadData)
        else { throw ExtractError.badResponse }
        return payload.tasks.compactMap { item in
            TaskExtractor.draft(
                title: item.title, day: item.day, start: item.start, durationMinutes: item.durationMinutes,
                important: item.important, urgent: item.urgent, project: item.project
            )
        }
    }

    /// Проверить ключ и модель без генерации (бесплатно): запрос описания модели.
    static func check(apiKey: String, model: String) async -> String {
        guard !apiKey.isEmpty else { return "Сначала сохрани ключ" }
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models/\(model)")!)
        request.timeoutInterval = 20
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(version, forHTTPHeaderField: "anthropic-version")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return "Непонятный ответ сервера" }
            if (200..<300).contains(http.statusCode) { return "Ключ работает, модель \(ClaudeSettings.title(of: model)) доступна" }
            return message(for: ExtractError.http(http.statusCode, errorMessage(in: data)))
        } catch {
            return message(for: error)
        }
    }

    /// Текст ошибки из тела ответа API: {"type":"error","error":{"type":…,"message":…}}.
    private static func errorMessage(in data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any] else { return nil }
        return error["message"] as? String
    }

    /// Что сказать пользователю.
    static func message(for error: Error) -> String {
        if let error = error as? ExtractError {
            switch error {
            case .noKey: return "Claude: ключ не задан"
            case .http(401, _), .http(403, _): return "Claude: ключ не принят — проверь его в настройках"
            case .http(404, _): return "Claude: модель недоступна для этого ключа — выбери другую в настройках"
            case .http(429, _): return "Claude: превышен лимит запросов — попробуй через минуту"
            case .http(529, _), .http(503, _): return "Claude перегружен — попробуй чуть позже"
            case .http(let code, let message):
                if let message, !message.isEmpty { return "Claude: \(message) (\(code))" }
                return "Claude: ошибка сервера \(code)"
            case .refusal: return "Claude отказался разбирать этот текст"
            case .truncated: return "Claude: ответ не поместился — продиктуй короче"
            case .badResponse: return "Claude: непонятный ответ"
            }
        }
        if let error = error as? URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dataNotAllowed:
                return "Claude: нет сети"
            case .timedOut:
                return "Claude не ответил вовремя"
            default:
                return "Claude: сеть — \(error.localizedDescription)"
            }
        }
        return "Claude: \(error.localizedDescription)"
    }
}
