import Foundation

/// Делит надиктованный текст на отдельные задачи. Чистая логика без распознавания речи:
/// границы — переносы строк (долгие паузы), конец предложения, слова-связки («а ещё», «потом»…)
/// и союз «и» / запятая между двумя кусками, в каждом из которых есть глагол в неопределённой форме
/// («позвонить маме и купить хлеб» — две задачи, «купить хлеб и молоко» — одна).
public enum DictationSplitter {
    /// Связки, после которых начинается новая задача (в начале или в середине фразы).
    public static let connectors: [String] = [
        "а ещё", "а еще", "и ещё", "и еще", "а потом", "и потом", "потом", "затем", "далее", "дальше",
        "а также", "также", "плюс", "следующая задача", "следующее", "новая задача",
        "во-вторых", "в-третьих", "во вторых", "в третьих", "второе", "третье", "четвёртое", "четвертое",
    ]

    public static func split(_ text: String) -> [String] {
        let withBreaks = text.replacingOccurrences(of: "[.!?;]+", with: "\n", options: .regularExpression)
        var pieces: [String] = []
        for line in withBreaks.components(separatedBy: "\n") {
            for part in splitByConnectors(line) {
                pieces.append(contentsOf: splitByConjunctions(part))
            }
        }
        return pieces.map(clean).filter { !$0.isEmpty }
    }

    // MARK: - Связки

    private static func splitByConnectors(_ line: String) -> [String] {
        var result = line
        // «ещё раз …» — не связка, а часть задачи.
        let alternatives = connectors.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        let pattern = "(^|[\\s,])(\(alternatives)|ещё(?!\\s+раз)|еще(?!\\s+раз))(?=[\\s,]|$)"
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "\n")
        }
        return result.components(separatedBy: "\n")
    }

    // MARK: - «и» и запятая между двумя действиями

    private static func splitByConjunctions(_ text: String) -> [String] {
        let parts = text.components(separatedBy: ",")
            .flatMap { $0.components(separatedBy: " и ") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard parts.count > 1 else { return [text] }
        // Склеиваем обратно всё, что не выглядит как два самостоятельных действия.
        var pieces: [String] = []
        var current = ""
        var cursor = text.startIndex
        for part in parts {
            guard let range = text.range(of: part, range: cursor..<text.endIndex) else { continue }
            let glue = String(text[cursor..<range.lowerBound])
            cursor = range.upperBound
            if current.isEmpty {
                current = part
            } else if hasVerb(current) && hasVerb(part) {
                pieces.append(current)
                current = part
            } else {
                current += glue + part
            }
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces
    }

    /// Есть ли глагол в неопределённой форме: «позвонить», «купить», «записаться», «помочь».
    static func hasVerb(_ text: String) -> Bool {
        text.range(of: "(^|\\s)[а-яё]{2,}(ть|ти|чь|ться|тись|чься)(?=[\\s,.!?:;]|$)",
                   options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func clean(_ text: String) -> String {
        let junk = CharacterSet(charactersIn: " ,;:-–—\n\t")
        var result = text.trimmingCharacters(in: junk)
        if result.lowercased().hasPrefix("и ") { result = String(result.dropFirst(2)) }
        return result.trimmingCharacters(in: junk)
    }
}
