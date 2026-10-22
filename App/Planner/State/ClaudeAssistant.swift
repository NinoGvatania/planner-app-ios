import Foundation
import PlannerCore

/// Ассистент в чате: по диктовке или тексту собирает список задач и правит его по просьбам
/// («поправь первую и третью, добавь ещё одну»). Каждый ответ — короткая реплика и полный текущий
/// список; в календарь задачи попадают, только когда пользователь нажал «Добавить».
enum ClaudeAssistant {
    /// Реплика разговора. У ответа ассистента — его список задач в том виде, в каком он сейчас на экране
    /// (с правками пользователя в карточках); `added` — пользователь нажал «Добавить».
    struct Turn {
        enum Role { case user, assistant }
        let role: Role
        let text: String
        var tasks: [DraftTask] = []
        var added = false
    }

    private struct Payload: Decodable {
        let reply: String
        let tasks: [ClaudeExtractor.Item]
    }

    static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "reply": ["type": "string", "description": "Короткая реплика по-русски: что сделал или что поменял"],
            "tasks": ["type": "array", "items": ClaudeExtractor.taskItemSchema],
        ],
        "required": ["reply", "tasks"],
        "additionalProperties": false,
    ]

    /// Правила разбора диктовки плюс правила разговора.
    static func systemPrompt(today: Date, vocabulary: DictationVocabulary) -> String {
        ClaudeExtractor.systemPrompt(today: today, vocabulary: vocabulary) + """

        Сейчас это разговор, а не одна расшифровка. Пользователь пишет или диктует (в надиктованном бывают \
        ошибки распознавания — правь их по правилам выше), ты собираешь список задач и правишь его по его просьбам.
        На каждое сообщение верни:
        - reply — одно-два коротких предложения по-русски: что сделал или что поменял; если что-то неясно — \
        короткий вопрос. Список задач в reply не пересказывай — он виден карточками.
        - tasks — ПОЛНЫЙ текущий список задач (не только изменения), в прежнем порядке; новые — в конец.
        Правки: «первая», «третья», «последняя», «вторую убери» — по номерам в текущем списке, с единицы. \
        «Добавь ещё …» — добавь. «Перенеси всё на завтра» — поменяй у всех. Остальные задачи возвращай \
        без изменений, слово в слово.
        Твои прошлые ответы показаны в том виде, в каком список сейчас на экране: пользователь мог сам \
        поправить или удалить карточки — исходи из этой версии.
        Если перед сообщением сказано, что задачи уже добавлены, тот список закрыт: собирай новый, \
        добавленные не повторяй. Нет новых задач — tasks пустой.
        Если сообщение не про задачи (вопрос, «спасибо»), ответь коротко в reply, а tasks верни как были.
        """
    }

    /// Ответ ассистента на последнюю реплику пользователя. Бросает `ClaudeExtractor.ExtractError` или `URLError`.
    static func reply(to turns: [Turn], apiKey: String, model: String,
                      vocabulary: DictationVocabulary) async throws -> (reply: String, drafts: [DraftTask]) {
        let text = try await ClaudeExtractor.send(
            model: model,
            system: systemPrompt(today: Date(), vocabulary: vocabulary),
            messages: messages(from: turns),
            schema: schema,
            apiKey: apiKey
        )
        guard let data = text.data(using: .utf8),
              let payload = try? JSONDecoder().decode(Payload.self, from: data)
        else { throw ClaudeExtractor.ExtractError.badResponse }
        let reply = payload.reply.trimmingCharacters(in: .whitespacesAndNewlines)
        return (reply, TaskExtractor.dedupe(ClaudeExtractor.drafts(from: payload.tasks)))
    }

    /// История для API: реплики пользователя как есть, ответы ассистента — в формате его ответа (с текущим
    /// списком). Что список добавлен, говорит следующая реплика пользователя. Подряд идущие реплики одной
    /// стороны (например, после ошибки сети) склеиваются: API ждёт чередования.
    static func messages(from turns: [Turn]) -> [[String: Any]] {
        var result: [[String: Any]] = []
        var addedBefore = false
        for turn in turns {
            let role: String
            var content: String
            switch turn.role {
            case .user:
                role = "user"
                content = turn.text
                if addedBefore {
                    content = "[Пользователь нажал «Добавить»: задачи из твоего прошлого списка уже в календаре.]\n" + content
                    addedBefore = false
                }
            case .assistant:
                role = "assistant"
                content = assistantJSON(reply: turn.text, tasks: turn.tasks)
                addedBefore = turn.added
            }
            if let last = result.last, last["role"] as? String == role, let previous = last["content"] as? String {
                result[result.count - 1]["content"] = previous + "\n\n" + content
            } else {
                result.append(["role": role, "content": content])
            }
        }
        // Разговор начинается с пользователя — иначе API не примет историю.
        while let first = result.first, first["role"] as? String != "user" { result.removeFirst() }
        return result
    }

    /// Ответ ассистента в формате схемы: так модель видит свой прошлый список с правками пользователя.
    private static func assistantJSON(reply: String, tasks: [DraftTask]) -> String {
        let iso = DateFormatter()
        iso.locale = Locale(identifier: "en_US_POSIX")
        iso.calendar = DayMath.calendar
        iso.timeZone = DayMath.calendar.timeZone
        iso.dateFormat = "yyyy-MM-dd"
        let items: [[String: Any]] = tasks.map { draft in
            let (important, urgent): (Int, Int)
            switch Quadrant(rawValue: draft.quadrantRaw) {
            case .urgentImportant: (important, urgent) = (1, 1)
            case .important: (important, urgent) = (1, 0)
            case .urgent: (important, urgent) = (0, 1)
            case .other: (important, urgent) = (-1, -1)
            case nil: (important, urgent) = (0, 0)
            }
            return [
                "title": draft.title,
                "day": draft.dayOffset.map { iso.string(from: DayMath.day(offset: $0)) } ?? "",
                "start": draft.start.map { String(format: "%02d:%02d", $0 / 60, $0 % 60) } ?? "",
                "durationMinutes": draft.duration,
                "important": important,
                "urgent": urgent,
                "project": draft.project,
                "note": draft.notes,
            ]
        }
        let object: [String: Any] = ["reply": reply, "tasks": items]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return reply }
        return text
    }
}
