import Foundation

/// Чистка надиктованной фразы: речевой мусор («ну», «короче», «как бы»), вводные «мне нужно» / «надо»,
/// повторы слов, лишние пробелы, заглавная буква. Правила, без модели.
public enum SpeechCleanup {
    /// Слова и обороты, которые выбрасываются где угодно.
    public static let fillers: [String] = [
        "ну", "короче", "типа", "как бы", "вот", "значит", "блин", "блядь", "блять", "бля", "нахуй", "нихуя",
        "ёпта", "епта", "это самое", "в общем", "в общем-то", "так сказать", "допустим", "в принципе",
        "эм", "э", "ммм", "мм", "ага", "окей", "ок", "вот это вот", "получается", "собственно",
        "по сути", "на самом деле", "в смысле", "то есть", "как бы там ни было", "ну вот", "ну это",
        "там", "привет", "ладно", "хуйня", "пиздец", "сука", "ёбаный", "ебаный", "ебать", "нахер", "на хер",
        "охуеть", "заебись", "ёпрст", "в рот", "хуй", "пиздато", "ёб твою мать", "еб твою мать",
    ]

    /// Вводные обороты в начале: «мне нужно позвонить» → «позвонить».
    public static let leadIns: [String] = [
        "мне нужно будет", "мне надо будет", "мне нужно", "мне надо", "нужно будет", "надо будет",
        "нужно", "надо", "надо бы", "нужно бы", "я хочу", "хочу", "я должен", "я должна", "должен", "должна",
        "не забыть", "не забыть бы", "не забудь", "напомни мне", "напомни", "давай", "давайте", "ещё", "еще",
        "потом", "затем", "также", "а также", "и", "а", "задача", "следующая задача", "новая задача",
        "я планирую", "планирую", "я собираюсь", "собираюсь", "мне бы", "было бы", "неплохо бы", "в общем",
        "первая задача", "вторая задача", "третья задача", "четвёртая задача", "четвертая задача", "пятая задача",
        "последняя задача", "ещё одна задача", "еще одна задача", "первое", "второе", "третье", "четвёртое",
        "четвертое", "пятое", "шестое", "последнее", "следующее", "во-первых", "во-вторых", "в-третьих",
        "сделать следующие вещи", "сделать следующее", "следующие вещи", "следующие задачи", "вот что",
        "так вот", "так", "итак", "значит", "короче", "мне нужно будет сделать", "нужно сделать", "надо сделать",
        "записать", "запиши", "добавь", "добавить задачу", "добавь задачу",
    ]

    /// Реплики, из которых задачи не бывает: приветствия, «как дела», «всё», «хватит».
    public static let junkPhrases: Set<String> = [
        "привет", "как дела", "что там", "всё", "все", "конец", "хватит", "стоп", "готово", "спасибо", "пока",
        "да", "нет", "ага", "угу", "ладно", "окей", "ок", "всё всё", "так", "ну", "у", "а", "и",
    ]

    /// Хвосты, которые остаются от связок: «… и», «… а», «… потом», «… чтобы».
    public static let trailingJunk: [String] = ["и", "а", "потом", "затем", "ну", "вот", "как бы", "чтобы", "чтоб", "это"]

    /// Подчистить готовое название: убрать хвосты-связки, двойные пробелы, точку в конце, заглавная буква.
    public static func tidyTitle(_ title: String) -> String {
        var words = title.split(separator: " ").map(String.init)
        while let last = words.last, trailingJunk.contains(last.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ",.;:!?"))) {
            words.removeLast()
        }
        let joined = words.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:!?-–—"))
        return capitalized(joined.isEmpty ? title : joined)
    }

    public static func clean(_ text: String) -> String {
        var result = " " + text.replacingOccurrences(of: "[\\s]+", with: " ", options: .regularExpression) + " "
        for filler in fillers.sorted(by: { $0.count > $1.count }) {
            let pattern = "\\s" + NSRegularExpression.escapedPattern(for: filler) + "(?=[\\s,.!?])"
            result = result.replacingOccurrences(of: pattern, with: " ", options: [.regularExpression, .caseInsensitive])
        }
        result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        result = result.trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:!?-–—"))
        // Вводные в начале — по одному слою за раз, пока что-то снимается.
        var stripped = true
        while stripped {
            stripped = false
            for lead in leadIns.sorted(by: { $0.count > $1.count }) {
                let pattern = "^" + NSRegularExpression.escapedPattern(for: lead) + "(?=\\s|$)"
                if let range = result.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                    result = String(result[range.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: " ,:-–—"))
                    stripped = true
                    break
                }
            }
        }
        result = collapseRepeats(result)
        return capitalized(result)
    }

    /// «задача задача задача» → «задача».
    static func collapseRepeats(_ text: String) -> String {
        var out: [String] = []
        for word in text.split(separator: " ").map(String.init) {
            if let last = out.last, last.caseInsensitiveCompare(word) == .orderedSame { continue }
            out.append(word)
        }
        return out.joined(separator: " ")
    }

    public static func capitalized(_ text: String) -> String {
        guard let first = text.first else { return text }
        return String(first).uppercased() + text.dropFirst()
    }

    /// Стоит ли вообще заводить задачу из куска: минимум два символа и не одно служебное слово.
    public static func isMeaningful(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:!?-–—\n\t"))
        guard trimmed.count >= 3 else { return false }
        let low = trimmed.lowercased()
        guard !junkPhrases.contains(low) else { return false }
        let words = low.split { !$0.isLetter && !$0.isNumber && $0 != "-" }.map(String.init)
        guard words.contains(where: { $0.count >= 3 }) else { return false }
        // Одни лишь служебные слова и междометия — не задача.
        let junk = junkPhrases.union(fillers).union(["это", "ты", "вы", "он", "она", "они", "мы", "я", "же", "бы", "ли", "дела"])
        return words.contains { !junk.contains($0) }
    }
}
