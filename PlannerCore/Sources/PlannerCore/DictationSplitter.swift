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
        "точка", "следующая",
    ]

    /// Короткие связки: жёстко делят в начале фразы или после запятой; в середине — только между действиями.
    public static let singleWordConnectors: [String] = [
        "потом", "затем", "далее", "дальше", "также", "плюс", "ещё", "еще",
    ]

    /// Порядковые маркеры: в начале фразы или после запятой делят всегда («второе — позвонить»),
    /// в середине — когда за ними (через «задача», «нужно», «мне»…) идёт действие:
    /// «первая задача любить Дашу вторая задача гладить кота» — две задачи, «посмотреть второе видео» — одна.
    public static let ordinalConnectors: [String] = [
        "первое", "первая", "второе", "вторая", "третье", "третья", "четвёртое", "четвертое", "четвёртая",
        "четвертая", "пятое", "пятая", "шестое", "шестая", "седьмое", "седьмая", "последнее", "последняя",
        "следующее",
    ]

    /// Слова между маркером и действием, которые не мешают делению: «вторая задача нужно будет купить…».
    static let markerSkip: Set<String> = [
        "задача", "задание", "дело", "пункт", "вещь", "момент", "нужно", "надо", "будет", "бы", "мне", "не",
        "забыть", "обязательно", "это", "значит", "короче", "ну", "вот", "ещё", "еще", "также", "потом", "затем",
        "и", "а",
    ]

    /// С этих слов начинается придаточное, а не новая задача: «сказать, что приеду», «узнать, когда…».
    static let subordinators: Set<String> = [
        "что", "чтобы", "чтоб", "когда", "если", "который", "которая", "которые", "которое", "которую", "где",
        "куда", "как", "ли", "пока", "хотя", "откуда", "зачем", "почему", "кто", "чего", "чем", "потому", "так",
        "сколько", "какой", "какая", "какие", "какое",
    ]

    /// Если кусок кончается на вопросительное или относительное слово, «надо/нужно» после него —
    /// часть придаточного («узнать, что нужно принести»), а не новая задача.
    static let relatives: Set<String> = [
        "что", "ли", "как", "сколько", "кто", "где", "когда", "куда", "зачем", "почему", "чего", "чем", "кого",
        "кому", "который", "которые", "которую", "какой", "какие",
    ]

    /// Вводные посреди фразы, за которыми начинается новое действие: «доработать текст надо отправить его».
    public static let midLeadIns: [String] = [
        "не забыть", "ещё надо", "еще надо", "ещё нужно", "еще нужно", "потом надо", "потом нужно",
        "также надо", "также нужно", "надо бы", "нужно бы", "надо", "нужно",
    ]

    /// Слова на -ть/-ти, которые не глаголы: числительные и существительные.
    static let notVerbs: Set<String> = [
        "пять", "шесть", "семь", "восемь", "девять", "десять", "одиннадцать", "двенадцать", "тринадцать",
        "четырнадцать", "пятнадцать", "шестнадцать", "семнадцать", "восемнадцать", "девятнадцать",
        "двадцать", "тридцать", "почти", "дети", "гости", "кровать", "тетрадь", "мать", "путь", "сеть",
        "части", "новости", "кости", "вести", "масти", "сласти", "ярость", "радость", "область", "скорость",
    ]

    /// Разделить текст на задачи. `linguistics` — части речи от платформы (NaturalLanguage на iPhone):
    /// с ними «купи хлеб и позвони маме» тоже делится на два действия.
    public static func split(_ text: String, linguistics: Linguistics? = nil) -> [String] {
        // Конец предложения; точка между цифрами («в 9.30») остаётся.
        let withBreaks = text.replacingOccurrences(of: "[!?;]+|(?<!\\d)\\.+|\\.+(?!\\d)", with: "\n", options: .regularExpression)
        var pieces: [String] = []
        for line in withBreaks.components(separatedBy: "\n") {
            for part in splitByHardConnectors(line) {
                for chunk in splitByOrdinals(part, linguistics: linguistics) {
                    pieces.append(contentsOf: splitByConjunctions(chunk, linguistics: linguistics))
                }
            }
        }
        return pieces.map(clean).filter { !$0.isEmpty }
    }

    // MARK: - Порядковые маркеры посреди фразы

    private static let wordPattern = try! NSRegularExpression(pattern: "[а-яёА-ЯЁa-zA-Z0-9-]+")

    private static func splitByOrdinals(_ text: String, linguistics: Linguistics?) -> [String] {
        let ns = text as NSString
        let matches = wordPattern.matches(in: text, range: NSRange(location: 0, length: ns.length))
        let words = matches.map { ns.substring(with: $0.range).lowercased() }
        var cuts: [Int] = []
        var index = 1
        while index < words.count {
            if ordinalConnectors.contains(words[index]) {
                var next = index + 1
                var skipped = 0
                while next < words.count, markerSkip.contains(words[next]), skipped < 4 {
                    next += 1
                    skipped += 1
                }
                if next < words.count, isActionWord(words[next], linguistics) {
                    cuts.append(matches[index].range.location)
                    index = next
                    continue
                }
            }
            index += 1
        }
        guard !cuts.isEmpty else { return [text] }
        var pieces: [String] = []
        var start = 0
        for cut in cuts {
            pieces.append(ns.substring(with: NSRange(location: start, length: cut - start)))
            start = cut
        }
        pieces.append(ns.substring(from: start))
        return pieces
    }

    /// Слово — действие: глагол по окончанию или по части речи от платформы. Если платформа
    /// считает слово существительным, окончание не спасает («запчасти», «кисть»).
    static func isActionWord(_ word: String, _ linguistics: Linguistics?) -> Bool {
        guard !notVerbs.contains(word) else { return false }
        let looksLikeInfinitive = hasVerb(word)
        guard let linguistics else { return looksLikeInfinitive }
        if linguistics.isVerb(word) { return true }
        return looksLikeInfinitive && !linguistics.isNoun(word)
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
        let single = (midLeadIns + singleWordConnectors).map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        let pattern = ",|\\s(?:и|\(single))(?!\\s+раз(?![а-яё]))(?=\\s)"
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()

    private static func splitByConjunctions(_ text: String, linguistics: Linguistics?) -> [String] {
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
            if hasAction(current, linguistics) && startsWithAction(next, linguistics) && !endsWithRelative(current) {
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

    /// Инфинитив по окончанию: «-ть/-ться/-чь/-чься» и закрытый набор на «-ти» («уйти», «принести»,
    /// «вывезти»…). Существительные вроде «запчасти», «сладости», «новости» сюда не попадают.
    private static let verbPattern = try! NSRegularExpression(
        pattern: "(?<![а-яё])(?:[а-яё]{2,}(?:ть|ться|чь|чься)|[а-яё]*(?:йти|нести|везти|вести|расти|идти|ползти|трясти|грести|плести|мести|цвести|брести))(?![а-яё])"
    )

    /// Есть ли в куске действие: глагол в неопределённой форме по окончанию, а с лингвистикой —
    /// любой глагол по части речи («купи», «позвони»). Числительные и существительные на «-ть» не в счёт.
    static func hasAction(_ text: String, _ linguistics: Linguistics?) -> Bool {
        words(in: text).contains { isActionWord($0.lowercased(), linguistics) }
    }

    /// Правая часть начинается с действия (после «задача», «нужно», «мне»…), а не с придаточного
    /// («что приеду», «когда будет время»).
    static func startsWithAction(_ text: String, _ linguistics: Linguistics?) -> Bool {
        let list = words(in: text).map { $0.lowercased() }
        var index = 0
        while index < list.count, index < 4, markerSkip.contains(list[index]) { index += 1 }
        guard index < list.count else { return false }
        if subordinators.contains(list[index]) { return false }
        return isActionWord(list[index], linguistics)
    }

    static func endsWithRelative(_ text: String) -> Bool {
        guard let last = words(in: text).last?.lowercased() else { return false }
        return relatives.contains(last)
    }

    /// Есть ли глагол в неопределённой форме: «позвонить», «купить», «записаться», «помочь».
    static func hasVerb(_ text: String) -> Bool {
        let low = text.lowercased()
        let ns = low as NSString
        return verbPattern.matches(in: low, range: NSRange(location: 0, length: ns.length)).contains { match in
            !notVerbs.contains(ns.substring(with: match.range))
        }
    }

    private static let trailingConnectors: Set<String> = ["и", "а", "потом", "затем", "ну", "вот", "надо", "нужно"]

    private static func clean(_ text: String) -> String {
        let junk = CharacterSet(charactersIn: " ,;:-–—\n\t")
        var result = text.trimmingCharacters(in: junk)
        if result.lowercased().hasPrefix("и ") { result = String(result.dropFirst(2)) }
        // Хвост-связка от деления: «позвонить маме и» → «позвонить маме».
        var words = result.split(separator: " ").map(String.init)
        while let last = words.last, trailingConnectors.contains(last.lowercased().trimmingCharacters(in: junk)) {
            words.removeLast()
        }
        result = words.joined(separator: " ")
        return result.trimmingCharacters(in: junk)
    }
}
