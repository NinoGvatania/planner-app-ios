import Foundation

/// Календарные вычисления и русские подписи дат.
enum DayMath {
    static var calendar: Calendar { Calendar.current }

    static let weekdayShort = ["вс", "пн", "вт", "ср", "чт", "пт", "сб"]
    static let weekdayFull = ["воскресенье", "понедельник", "вторник", "среда", "четверг", "пятница", "суббота"]
    static let monthGenitive = ["января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября", "ноября", "декабря"]
    static let monthShort = ["янв", "фев", "мар", "апр", "мая", "июн", "июл", "авг", "сен", "окт", "ноя", "дек"]

    /// Начало сегодняшнего дня.
    static func today() -> Date {
        calendar.startOfDay(for: Date())
    }

    /// Начало дня со смещением от сегодняшнего.
    static func day(offset: Int) -> Date {
        calendar.date(byAdding: .day, value: offset, to: today()) ?? today()
    }

    /// Смещение дня от сегодняшнего.
    static func offset(of day: Date) -> Int {
        calendar.dateComponents([.day], from: today(), to: calendar.startOfDay(for: day)).day ?? 0
    }

    /// Текущее время в минутах от 0:00.
    static func nowMinutes(at date: Date = Date()) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// Смещение понедельника той недели, в которую входит день со смещением `offset`.
    static func weekStartOffset(containing offset: Int) -> Int {
        let sinceMonday = (weekdayIndex(day(offset: offset)) + 6) % 7
        return offset - sinceMonday
    }

    /// Начало месяца, в который входит день.
    static func monthStart(of date: Date) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date)) ?? date
    }

    /// Месяц со смещением от месяца данного дня (число дня сохраняется, если есть).
    static func date(_ date: Date, addingMonths months: Int) -> Date {
        calendar.date(byAdding: .month, value: months, to: date) ?? date
    }

    static let monthNominative = ["Январь", "Февраль", "Март", "Апрель", "Май", "Июнь", "Июль", "Август", "Сентябрь", "Октябрь", "Ноябрь", "Декабрь"]

    static func year(_ date: Date) -> Int {
        calendar.component(.year, from: date)
    }

    /// 0 — воскресенье … 6 — суббота.
    static func weekdayIndex(_ date: Date) -> Int {
        calendar.component(.weekday, from: date) - 1
    }

    static func dayOfMonth(_ date: Date) -> Int {
        calendar.component(.day, from: date)
    }

    static func monthIndex(_ date: Date) -> Int {
        calendar.component(.month, from: date) - 1
    }

    /// «20 октября».
    static func title(offset: Int) -> String {
        let date = day(offset: offset)
        return "\(dayOfMonth(date)) \(monthGenitive[monthIndex(date)])"
    }

    /// «Сегодня, вторник».
    static func subtitle(offset: Int) -> String {
        let date = day(offset: offset)
        let prefix = offset == 0 ? "Сегодня, " : (offset == 1 ? "Завтра, " : "")
        return prefix + weekdayFull[weekdayIndex(date)]
    }

    /// «сегодня», «завтра», «вс, 18 окт».
    static func label(offset: Int) -> String {
        switch offset {
        case 0: return "сегодня"
        case 1: return "завтра"
        case 2: return "послезавтра"
        case -1: return "вчера"
        default:
            let date = day(offset: offset)
            return "\(weekdayShort[weekdayIndex(date)]), \(dayOfMonth(date)) \(monthShort[monthIndex(date)])"
        }
    }

    /// Полная подпись для доступности: «вторник, 20 октября».
    static func accessibilityLabel(offset: Int) -> String {
        let date = day(offset: offset)
        return "\(weekdayFull[weekdayIndex(date)]), \(dayOfMonth(date)) \(monthGenitive[monthIndex(date)])"
    }

    /// Русское склонение: plural(3, "задача", "задачи", "задач").
    static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let m10 = n % 10
        let m100 = n % 100
        if m10 == 1, m100 != 11 { return one }
        if (2...4).contains(m10), !(12...14).contains(m100) { return few }
        return many
    }
}
