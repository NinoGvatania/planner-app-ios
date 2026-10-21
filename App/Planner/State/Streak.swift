import Foundation

/// Серия дней подряд, в которые сделана хотя бы одна задача (мотивация в духе Duolingo).
/// Сегодняшний день без сделанных задач серию ещё не рвёт: она «живёт» до конца дня.
enum Streak {
    struct Info: Equatable {
        /// Текущая серия в днях (0 — серии нет).
        var current: Int
        /// Лучшая серия за всё время.
        var best: Int
        /// Сделано сегодня.
        var todayDone: Int
        /// Понедельник…воскресенье текущей недели: был ли день «закрыт».
        var week: [Bool]
        /// Сегодня уже что-то сделано.
        var todayClosed: Bool { todayDone > 0 }
    }

    static func compute(_ tasks: [PlannerTask], today: Date = DayMath.today()) -> Info {
        let cal = DayMath.calendar
        var days = Set<Date>()
        var todayDone = 0
        for task in tasks where task.isDone {
            guard let completed = task.completedAt else { continue }
            let day = cal.startOfDay(for: completed)
            days.insert(day)
            if day == today { todayDone += 1 }
        }
        // Текущая: считаем назад от сегодня, либо от вчера, если сегодня ещё пусто.
        var cursor = days.contains(today) ? today : (cal.date(byAdding: .day, value: -1, to: today) ?? today)
        var current = 0
        while days.contains(cursor) {
            current += 1
            guard let previous = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        // Лучшая: самый длинный отрезок подряд.
        var best = 0
        for day in days {
            guard let previous = cal.date(byAdding: .day, value: -1, to: day), !days.contains(previous) else { continue }
            var length = 0
            var walk = day
            while days.contains(walk) {
                length += 1
                guard let next = cal.date(byAdding: .day, value: 1, to: walk) else { break }
                walk = next
            }
            best = max(best, length)
        }
        let monday = DayMath.day(offset: DayMath.weekStartOffset(containing: 0))
        let week = (0..<7).map { index -> Bool in
            let day = cal.date(byAdding: .day, value: index, to: monday) ?? monday
            return days.contains(day)
        }
        return Info(current: current, best: max(best, current), todayDone: todayDone, week: week)
    }
}
