import Foundation
import PlannerCore

/// Настройки разбора диктовки через Claude: свой ключ API (в связке ключей iPhone), модель, вкл/выкл.
enum ClaudeSettings {
    static let keyAccount = "anthropicAPIKey"
    static let enabledKey = "claudeEnabled"
    static let modelKey = "claudeModel"
    static let defaultModel = "claude-opus-5-5"
    static let models: [(id: String, title: String)] = [
        ("claude-opus-5-5", "Opus 5.5 — точнее всех, пара центов за диктовку"),
        ("claude-sonnet-5-5", "Sonnet 5.5 — быстрее, около цента"),
        ("claude-haiku-5-5", "Haiku 5.5 — самый быстрый, доли цента"),
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
        let note: String
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
                        "note": ["type": "string", "description": "Важные подробности по-русски или пустая строка"],
                    ],
                    "required": ["title", "day", "start", "durationMinutes", "important", "urgent", "project", "note"],
                    "additionalProperties": false,
                ],
            ],
        ],
        "required": ["tasks"],
        "additionalProperties": false,
    ]

    /// Слова пользователя для промпта: так он сам пишет свои названия, имена и сокращения.
    private static func vocabularyLine(_ words: [String]) -> String {
        guard !words.isEmpty else { return "" }
        return "\nСлова пользователя (его проекты и прежние задачи — так он пишет свои названия и имена): "
            + words.joined(separator: "; ") + "."
    }

    /// Инструкция с сегодняшней датой и ближайшими днями недели — чтобы «в пятницу» превращалось в точную дату.
    static func systemPrompt(today: Date, vocabulary: [String] = []) -> String {
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
        let tomorrowISO = calendar.date(byAdding: .day, value: 1, to: start).map { iso.string(from: $0) } ?? ""
        let nextDays = (1...7).compactMap { offset -> String? in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return "\(weekday.string(from: date)) — \(iso.string(from: date))"
        }.joined(separator: ", ")
        return """
        Ты — постобработка голосовой диктовки в личном планировщике. На входе сырая расшифровка \
        распознавания речи на русском: пунктуации может не быть, встречаются оговорки, повторы, \
        слова-паразиты и неверно распознанные слова. Пойми, что человек собирается сделать, \
        и преврати это в аккуратный список задач. Пиши по-русски.

        Сегодня \(long.string(from: today)) (\(iso.string(from: today))). Ближайшие дни: \(nextDays). \
        Неделя начинается с понедельника.
        \(vocabularyLine(vocabulary))

        Как работать:
        1. Сначала прочитай весь текст целиком и пойми контекст: о каких делах, днях, людях и местах идёт речь.
        2. Исправь ошибки распознавания. Распознавание не знает редких слов, названий и имён и подставляет \
        вместо них похожие по звучанию обычные слова или искажённое написание, а ещё склеивает и разрывает \
        слова. Если слово выбивается из смысла фразы, восстанови то, что человек скорее всего сказал, \
        по звучанию и контексту. Если похожее по звучанию слово есть среди слов пользователя (список выше, если он дан), \
        бери его написание: «тендог» при слове пользователя «Тендок» → «Тендок». Незнакомое название или имя, \
        которого среди них нет, оставь как распознано (название — с заглавной буквы), не заменяй его другим \
        известным словом. Числа, суммы, время, номера телефонов и адреса не меняй. Смысл сказанного не меняй \
        никогда: не уверен — оставь как есть.
        3. Раздели на задачи: одна задача — одно самостоятельное действие, которое можно отметить сделанным.
        - Одно действие не дроби. Однотипные покупки за один поход — одна задача с обобщающим названием \
        («Купить продукты», «Купить канцтовары»), сам перечень — в note; покупка другого рода или в другом \
        месте (подарок, лекарства в аптеке) — отдельная задача. \
        «Позвонить Пете и сказать про встречу» — одна задача: звонок ради сообщения, сообщение — в note.
        - Разные действия — разные задачи, даже если связаны «и», «потом», «а ещё», «и ещё».
        - Если человек повторил или уточнил ту же задачу, оставь одну — в уточнённом виде.
        4. Контекст распространяется: день, сказанный для группы дел («в пятницу надо: …», «завтра: …»), \
        относится ко всем делам группы. Одно общее время на несколько дел («завтра с утра: …») ставь только \
        первому делу, остальным — без времени, чтобы они не легли в одно и то же время. Местоимения и отсылки \
        («ему», «туда», «это», «то же самое») раскрывай в явные имена и предметы из текста.
        5. Выдели смысл. title — суть: коротко (обычно до шести слов), глагол в неопределённой форме первым \
        («Позвонить маме», «Записаться к стоматологу»), без точки в конце. note — важные подробности: что \
        именно, кому, сколько, номер, адрес, список, причина, срок вроде «до обеда» или «до пятницы». \
        Коротко, без воды; нет подробностей — пустая строка.
        6. Ничего не выдумывай: только сказанное или то, что явно следует из контекста. Рассуждения, эмоции, \
        приветствия и комментарии пропускай; но намерение внутри рассуждения («надо бы наконец записаться \
        к врачу») — это задача.

        Поля:
        - day: «сегодня», «завтра», «послезавтра», день недели (ближайший будущий) и даты переводи \
        в YYYY-MM-DD по списку выше; не назван — пустая строка. Срок «до пятницы» — это не день задачи: \
        day пустой, срок — в note.
        - start: время начала «HH:MM» в 24-часовом формате, по тем же правилам, что у быстрого ввода:
          «в 9:30» → 09:30, «в 10» → 10:00, «в час дня» → 13:00, «в 12 ночи» → 00:00;
          число от 1 до 6 без уточнения — после полудня: «в 3» → 15:00, «в пять» → 17:00, \
        «в половине третьего» → 14:30;
          «утром», «днём», «вечером», «ночью» без числа → 09:00, 14:00, 19:00, 23:00; с числом они задают \
        половину суток: «вечером в 7» → 19:00, «в 7 утра» → 07:00;
          время не названо — пустая строка.
        - durationMinutes: только если длительность названа («на час» → 60, «минут на сорок» → 40); иначе 0.
        - important / urgent: 1 — прямо сказано «важно» / «срочно», -1 — «не важно» / «не срочно», иначе 0.
        - project: название после «по проекту …» или «#…»; иначе пустая строка.

        В ответе day — всегда дата YYYY-MM-DD или пустая строка, никогда не слово.

        Пример (завтра — \(tomorrowISO)). Расшифровка: «так короче завтра надо позвонить петру насчёт машины \
        ну и сказать ему что заберу её в субботу а ещё купить молоко хлеб и яйца и это самое важно отправить \
        отчёт до обеда».
        Задачи:
        - «Позвонить Петру насчёт машины»: day — \(tomorrowISO), start — пусто, note — «Сказать, что заберу \
        машину в субботу».
        - «Купить продукты»: day — \(tomorrowISO), start — пусто, note — «Молоко, хлеб, яйца».
        - «Отправить отчёт»: day — \(tomorrowISO), start — пусто, important — 1, note — «До обеда».
        """
    }

    /// Разобрать текст. Бросает `ExtractError` или `URLError`.
    static func extract(_ transcript: String, apiKey: String, model: String, vocabulary: [String] = []) async throws -> [DraftTask] {
        guard !apiKey.isEmpty else { throw ExtractError.noKey }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        // Ответ без потоковой передачи приходит целиком, когда модель закончит, — ждём с запасом.
        request.timeoutInterval = 180
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(version, forHTTPHeaderField: "anthropic-version")
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            "system": systemPrompt(today: Date(), vocabulary: vocabulary),
            "messages": [["role": "user", "content": "Расшифровка:\n\(transcript)"]],
            // Средняя глубина размышлений: на контекст и смысл хватает, а ждать и платить меньше.
            "output_config": ["effort": "medium", "format": ["type": "json_schema", "schema": schema]],
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
                important: item.important, urgent: item.urgent, project: item.project, note: item.note
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
            if (200..<300).contains(http.statusCode) {
                return "Ключ принят, модель \(ClaudeSettings.title(of: model)) доступна. Баланс так не проверить — он проверится при первом разборе"
            }
            return message(for: ExtractError.http(http.statusCode, errorMessage(in: data)))
        } catch {
            return message(for: error)
        }
    }

    /// Тип и текст ошибки из тела ответа API: {"type":"error","error":{"type":…,"message":…}} → «тип: текст».
    private static func errorMessage(in data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = json["error"] as? [String: Any] else { return nil }
        let type = error["type"] as? String ?? ""
        let message = error["message"] as? String ?? ""
        return type.isEmpty ? message : type + ": " + message
    }

    /// Что сказать пользователю.
    static func message(for error: Error) -> String {
        if let error = error as? ExtractError {
            switch error {
            case .noKey: return "Claude: ключ не задан"
            case .http(401, _): return "Claude: ключ не принят — проверь его в настройках"
            case .http(402, _): return "Claude: на балансе API нет средств — пополни на console.anthropic.com"
            case .http(400, let message?) where message.localizedCaseInsensitiveContains("credit balance")
                || message.contains("billing_error"):
                return "Claude: на балансе API нет средств — пополни на console.anthropic.com"
            case .http(403, let message):
                return "Claude: доступ запрещён (403) — API недоступен для этого аккаунта или региона"
                    + (message.map { ". Ответ сервера: \($0)" } ?? "")
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
