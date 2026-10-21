import Foundation

/// Разбор строки быстрого ввода по‑русски. Правила перенесены из `parse()` прототипа один в один
/// (см. `docs/PLAN.md`, раздел «Быстрый ввод»).
public struct QuickAddParser {
    public var calendar: Calendar
    public var today: Date

    public init(calendar: Calendar = .current, today: Date = Date()) {
        self.calendar = calendar
        self.today = today
    }

    /// Команда или новая задача.
    public func parse(_ text: String) -> QuickAddCommand {
        let low = normalized(text).trimmingCharacters(in: .whitespacesAndNewlines)
        if low.contains("просроч"),
           low.range(of: "перенес|разлож|раскида|перекин|постав", options: .regularExpression) != nil {
            return .fitOverdue(dayOffset: low.contains("завтра") ? 1 : 0)
        }
        if low.range(of: "^(что|какие|покажи|расскажи)(?=\\s|$)", options: .regularExpression) != nil {
            let day = low.contains("послезавтра") ? 2 : (low.contains("завтра") ? 1 : 0)
            return .agenda(dayOffset: day)
        }
        return .task(parseTask(text))
    }

    /// Разбор строки как новой задачи.
    public func parseTask(_ text: String) -> ParsedTask {
        var source = " " + text + " "
        // Точка, восклицательный и вопросительный знак после слова не ломают разбор («в 9:30.»).
        source = source.replacingOccurrences(of: "[.!?]+(?=\\s|$)", with: " ", options: .regularExpression)
        source = source.replacingOccurrences(of: ";|,(?=\\s|$)", with: " ", options: .regularExpression)
        let scanner = TextScanner(source)
        let tail = "(?=[\\s.,:;!?])"

        var result = ParsedTask(title: "", dayOffset: nil, start: nil)

        // Квадрант: !1–!4 или слова «важно» / «срочно» в любой форме, с «не».
        var important: Bool?
        var urgent: Bool?
        var explicitQuadrant = false
        if let m = scanner.take("\\s!([1-4])(?=\\s)"), let n = Int(m[1] ?? ""), let q = Quadrant(rawValue: n) {
            result.quadrant = q
            explicitQuadrant = true
        }
        while let m = scanner.take("\\s(не\\s?)?(важн|срочн)[а-я]*" + tail) {
            let negated = !(m[1] ?? "").isEmpty
            if m[2] == "важн" {
                important = !negated
            } else {
                urgent = !negated
            }
        }
        if !explicitQuadrant, important != nil || urgent != nil {
            result.quadrant = Quadrant(important: important ?? false, urgent: urgent ?? false)
        }

        // Проект: #учёба
        if let m = scanner.take("\\s#([0-9a-zа-я_-]+)" + tail) {
            let span = (m[0] ?? "").trimmingCharacters(in: .whitespaces)
            result.project = capitalized(String(span.dropFirst()))
        }

        // День.
        if scanner.take("\\sсегодня" + tail) != nil {
            result.dayOffset = 0
        } else if scanner.take("\\sпослезавтра" + tail) != nil {
            result.dayOffset = 2
        } else if scanner.take("\\sзавтра" + tail) != nil {
            result.dayOffset = 1
        } else if let m = scanner.take("\\s(?:в|во)\\s(понедельник|вторник|среду|четверг|пятницу|субботу|воскресенье)" + tail) {
            let index: [String: Int] = [
                "воскресенье": 0, "понедельник": 1, "вторник": 2, "среду": 3,
                "четверг": 4, "пятницу": 5, "субботу": 6,
            ]
            if let target = index[m[1] ?? ""] {
                let todayIndex = calendar.component(.weekday, from: today) - 1
                var diff = (target - todayIndex + 7) % 7
                if diff == 0 { diff = 7 }
                result.dayOffset = diff
            }
        }

        // Длительность.
        if scanner.take("\\s(?:на\\s)?полчаса" + tail) != nil {
            result.duration = 30
        } else if scanner.take("\\s(?:на\\s)?полтора\\sчаса" + tail) != nil {
            result.duration = 90
        } else if let m = scanner.take("\\s(?:на\\s)?(\\d{1,3})\\s?(?:минуты|минуту|минут|мин)" + tail), let n = Int(m[1] ?? "") {
            result.duration = max(5, n)
        } else if let m = scanner.take("\\sна\\s(\\d{1,2}(?:[.,]5)?)\\s?(?:часов|часа|час|ч)" + tail),
                  let hours = Double((m[1] ?? "").replacingOccurrences(of: ",", with: ".")) {
            result.duration = Int((hours * 60).rounded())
        } else if scanner.take("\\sна\\sчас" + tail) != nil {
            result.duration = 60
        }

        // Часть суток — задаёт половину суток для числа или время по умолчанию.
        var partOfDay: String?
        if scanner.take("\\sутром" + tail) != nil {
            partOfDay = "утра"
        } else if scanner.take("\\sднем" + tail) != nil {
            partOfDay = "дня"
        } else if scanner.take("\\sвечером" + tail) != nil {
            partOfDay = "вечера"
        } else if scanner.take("\\sночью" + tail) != nil {
            partOfDay = "ночи"
        }

        // Время.
        let words: [String: Int] = [
            "час": 1, "два": 2, "три": 3, "четыре": 4, "пять": 5, "шесть": 6, "семь": 7,
            "восемь": 8, "девять": 9, "десять": 10, "одиннадцать": 11, "двенадцать": 12,
        ]
        var hour: Int?
        var minute = 0
        var qualifier: String?
        if let m = scanner.take("\\s(?:в|к|на)\\s(\\d{1,2})[:.](\\d{2})(?:\\s(утра|дня|вечера|ночи))?" + tail) {
            hour = Int(m[1] ?? "")
            minute = Int(m[2] ?? "") ?? 0
            qualifier = nonEmpty(m[3])
        } else if let m = scanner.take("\\s(?:в|к)\\s(\\d{1,2})(?:\\s?(?:часов|часа|час|ч))?(?:\\s(утра|дня|вечера|ночи))?" + tail) {
            hour = Int(m[1] ?? "")
            qualifier = nonEmpty(m[2])
        } else if let m = scanner.take("\\s(?:в|к)\\s(час|два|три|четыре|пять|шесть|семь|восемь|девять|десять|одиннадцать|двенадцать)(?:\\s(утра|дня|вечера|ночи))?" + tail) {
            hour = words[m[1] ?? ""]
            qualifier = nonEmpty(m[2])
        } else if scanner.take("\\s(?:в\\s)?полдень" + tail) != nil {
            hour = 12
        } else if partOfDay == "утра" {
            hour = 9
        } else if partOfDay == "дня" {
            hour = 14
        } else if partOfDay == "вечера" {
            hour = 19
        } else if partOfDay == "ночи" {
            hour = 23
        }

        if var h = hour {
            let q = qualifier ?? partOfDay
            if q == "вечера", h < 12 {
                h += 12
            } else if q == "дня", h <= 6 {
                h += 12
            } else if q == "ночи", h == 12 {
                h = 0
            } else if q == nil, h >= 1, h <= 6 {
                h += 12
            }
            if (0...23).contains(h), (0...59).contains(minute) {
                result.start = h * 60 + minute
                if result.dayOffset == nil { result.dayOffset = 0 }
            }
        }

        // Название: остаток строки без мусора на краях.
        var title = scanner.remainder
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        for _ in 0..<3 {
            title = title.replacingOccurrences(of: "^[.,:;!?–—-]+\\s*", with: "", options: .regularExpression)
            title = title.replacingOccurrences(of: "\\s*[.,:;!?–—-]+$", with: "", options: .regularExpression)
            title = title.replacingOccurrences(of: "^(?:но|и|а|зато|только)\\s+", with: "", options: [.regularExpression, .caseInsensitive])
            title = title.replacingOccurrences(of: "\\s+(?:и|но|а|зато|только)$", with: "", options: [.regularExpression, .caseInsensitive])
            title = title.replacingOccurrences(of: "\\s+(?:и|но|а)\\s+(?=(?:и|но|а)\\s)", with: " ", options: [.regularExpression, .caseInsensitive])
        }
        result.title = title.isEmpty ? "Новая задача" : capitalized(title)
        if let start = result.start, start + result.duration > ClockGrid.dayEnd {
            result.duration = max(15, ClockGrid.dayEnd - start)
        }
        return result
    }

    // MARK: - Вспомогательное

    private func normalized(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "ё", with: "е")
    }

    private func nonEmpty(_ s: String?) -> String? {
        guard let s = s, !s.isEmpty else { return nil }
        return s
    }

    private func capitalized(_ s: String) -> String {
        guard let first = s.first else { return s }
        return String(first).uppercased() + s.dropFirst()
    }
}

/// Два параллельных текста: строчный для поиска и исходный для названия.
/// Найденный фрагмент заменяется пробелом в обоих.
final class TextScanner {
    private var low: String
    private var original: String

    init(_ text: String) {
        let lowText = text.lowercased().replacingOccurrences(of: "ё", with: "е")
        low = lowText
        // Если регистр изменил длину (редкие символы), название берём из строчного текста.
        original = lowText.utf16.count == text.utf16.count ? text : lowText
    }

    /// Остаток исходного текста после всех изъятий.
    var remainder: String { original }

    /// Ищет шаблон в строчном тексте. Возвращает `[фрагмент исходного текста, группа 1, группа 2, …]`
    /// (группы — из строчного текста, `nil` если группа не участвовала) и изымает найденное.
    func take(_ pattern: String) -> [String?]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let lowNS = NSString(string: low)
        let originalNS = NSString(string: original)
        let range = NSRange(location: 0, length: lowNS.length)
        guard let match = regex.firstMatch(in: low, options: [], range: range) else { return nil }
        var groups: [String?] = [originalNS.substring(with: match.range)]
        if match.numberOfRanges > 1 {
            for i in 1..<match.numberOfRanges {
                let r = match.range(at: i)
                groups.append(r.location == NSNotFound ? nil : lowNS.substring(with: r))
            }
        }
        low = lowNS.replacingCharacters(in: match.range, with: " ")
        original = originalNS.replacingCharacters(in: match.range, with: " ")
        return groups
    }
}
