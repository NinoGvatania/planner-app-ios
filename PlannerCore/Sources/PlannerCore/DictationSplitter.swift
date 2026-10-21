import Foundation

/// Делит надиктованный текст на отдельные задачи. Чистая логика без распознавания речи:
/// границы — переносы строк (долгие паузы), конец предложения, связки из нескольких слов
/// («а ещё», «а потом», «следующая задача») в любом месте, короткие связки («потом», «ещё», «второе»)
/// в начале фразы или после запятой, а в середине — «и», запятая и короткие связки между двумя
/// действиями с глаголом в неопределённой форме («позвонить маме и купить хлеб» — две задачи,
/// «купить хлеб и молоко», «купить ещё молока» — одна).
public enum DictationSplitter {
    /// Связки из нескольких слов: новая задача начинается после них где угодно.
    public static let multiWordConnectors: [String] = [
        "а ещё", "а еще", "и ещё", "и еще", "а потом", "и потом", "а затем", "а также",
        "следующая задача", "новая задача", "во-вторых", "в-третьих", "во вторых", "в третьих",
    ]

    /// Короткие связки: жёстко делят в начале фразы или после запятой; в середине — только между действиями.
    public static let singleWordConnectors: [String] = [
        "потом", "затем", "далее", "дальше", "также", "плюс", "ещё", "еще",
    ]

    /// Порядковые: только в начале фразы или после запятой («второе — позвонить»).
    public static let ordinalConnectors: [String] = [
        "второе", "третье", "четвёртое", "четвертое", "следующее",
    ]

    /// Слова на -ть/-ти, которые не глаголы: числительные и существительные.
    static let notVerbs: Set<String> = [
        "пять", "шесть", "семь", "восемь", "девять", "десять", "одиннадцать", "двенадцать", "тринадцать",
        "четырнадцать", "пятнадцать", "шестнадцать", "семнадцать", "восемнадцать", "девятнадцать",
        "двадцать", "тридцать", "почти", "дети", "гости", "кровать", "тетрадь", "мать", "путь", "сеть",
        "части", "новости", "кости", "вести", "масти", "сласти", "ярость", "радость", "область", "скорость",
    ]

    public static func split(_ text: String) -> [String] {
        // Конец предложения; точка между цифрами («в 9.30») остаётся.
        let withBreaks = text.replacingOccurrences(of: "[!?;]+|(?<!\\d)\\.+|\\.+(?!\\d)", with: "\n", options: .regularExpression)
        var pieces: [String] = []
        for line in withBreaks.components(separatedBy: "\n") {
            for part in splitByHardConnectors(line) {
                pieces.append(contentsOf: splitByConjunctions(part))
            }
        }
        return pieces.map(clean).filter { !$0.isEmpty }
    }

    // MARK: - Жёсткие связки

    private static let hardPattern: NSRegularExpression = {
        let multi = multiWordConnectors.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        let single = (singleWordConnectors + ordinalConnectors).map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        // «ещё раз …» — не связка, а часть задачи.
        let pattern = "(^|[\\s,])(?:\(multi))(?=[\\s,]|$)|(^\\s*|,\\s*)(?:\(single))(?!\\s+раз(?![а-яё]))(?=[\\s,]|$)"
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()

    private static func splitByHardConnectors(_ line: String) -> [String] {
        let replaced = hardPattern.stringByReplacingMatches(in: line, range: NSRange(line.startIndex..., in: line), withTemplate: "\n")
        return replaced.components(separatedBy: "\n")
    }

    // MARK: - «и», запятая и короткие связки между двумя действиями

    private static let softPattern: NSRegularExpression = {
        let single = singleWordConnectors.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        let pattern = ",|\\s(?:и|\(single))(?!\\s+раз(?![а-яё]))(?=\\s)"
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()

    private static func splitByConjunctions(_ text: String) -> [String] {
        let ns = text as NSString
        let matches = softPattern.matches(in: text, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return [text] }
        var segments: [(text: String, separator: String)] = []
        var cursor = 0
        for match in matches {
            segments.append((ns.substring(with: NSRange(location: cursor, length: match.range.location - cursor)), ""))
            segments[segments.count - 1].separator = ""
            cursor = match.range.location + match.range.length
            segments.append(("", ns.substring(with: match.range)))
        }
        segments.append((ns.substring(from: cursor), ""))
        // Склеиваем: segments чередуются [текст, разделитель, текст, разделитель, …, текст].
        var pieces: [String] = []
        var current = segments[0].text
        var index = 1
        while index + 1 < segments.count {
            let separator = segments[index].separator
            let next = segments[index + 1].text
            if hasVerb(current) && hasVerb(next) {
                pieces.append(current)
                current = next
            } else {
                current += separator + next
            }
            index += 2
        }
        pieces.append(current)
        return pieces
    }

    private static let verbPattern = try! NSRegularExpression(
        pattern: "(?<![а-яё])[а-яё]{2,}(?:ть|ти|чь|ться|тись|чься)(?![а-яё])"
    )

    /// Есть ли глагол в неопределённой форме: «позвонить», «купить», «записаться», «помочь».
    static func hasVerb(_ text: String) -> Bool {
        let low = text.lowercased()
        let ns = low as NSString
        return verbPattern.matches(in: low, range: NSRange(location: 0, length: ns.length)).contains { match in
            !notVerbs.contains(ns.substring(with: match.range))
        }
    }

    private static func clean(_ text: String) -> String {
        let junk = CharacterSet(charactersIn: " ,;:-–—\n\t")
        var result = text.trimmingCharacters(in: junk)
        if result.lowercased().hasPrefix("и ") { result = String(result.dropFirst(2)) }
        return result.trimmingCharacters(in: junk)
    }
}
