import Foundation
import PlannerCore
import WidgetKit

/// Пишет снимок сегодняшнего дня для виджета и просит WidgetKit перерисоваться.
enum WidgetBridge {
    static func update(_ tasks: [PlannerTask]) {
        let today = DayMath.today()
        let tomorrow = DayMath.day(offset: 1)
        let streak = Streak.compute(tasks, today: today)
        let overdue = tasks
            .filter { $0.isOverdue(today: today) }
            .sorted { ($0.day ?? today, $0.start ?? 0) < ($1.day ?? today, $1.start ?? 0) }
        let items = dayItems(tasks, on: today, today: today)
        let doneTodayInItems = items.filter { $0.doneToday == true }.count
        let snapshot = WidgetSnapshot(
            day: today,
            items: items,
            streak: streak.current,
            overdue: overdue.count,
            backlog: tasks.filter { $0.isInBacklog && !$0.isDone }.count,
            overdueItems: overdue.prefix(12).map { item($0, today: today, withDay: true) },
            // Весь завтрашний день: после полуночи, пока приложение не открыли, он станет сегодняшним.
            tomorrowItems: dayItems(tasks, on: tomorrow, today: today),
            // Серия без сегодняшнего дня: виджет сам прибавит день, когда сегодня что-то сделано.
            streakBefore: streak.todayClosed ? streak.current - 1 : streak.current,
            // Сделанное сегодня не из списков снимка: задачи бэклога, других дней.
            doneElsewhere: max(0, streak.todayDone - doneTodayInItems),
            bestStreak: streak.best,
            week: streak.week
        )
        guard !snapshot.hasSameContent(as: WidgetSnapshot.load()) else { return }
        do {
            try snapshot.save()
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            // Нет контейнера группы — виджет покажет заглушку, приложение работает как прежде.
        }
    }

    /// Действия в виджете, сделанные, пока приложение было в фоне, — по порядку: галочки (поставил и снял —
    /// задача открыта) и «На сегодня» для просроченных. Возвращает, поменялось ли что-нибудь.
    @discardableResult
    static func applyPendingActions(to tasks: [PlannerTask]) -> Bool {
        let actions = WidgetActions.load()
        guard let last = actions.last?.at else { return false }
        var changed = false
        for action in actions {
            switch action.kind {
            case .setDone:
                guard let id = action.id, let task = tasks.first(where: { $0.id == id }), task.isDone != action.done
                else { continue }
                task.isDone = action.done
                // Время галочки, а не открытия приложения: иначе серия засчитает не тот день.
                task.completedAt = action.done ? action.at : nil
                changed = true
            case .overdueToToday:
                // Как «На сегодня» в листе «Просрочено»: на день, когда нажали, на весь день.
                let day = DayMath.calendar.startOfDay(for: action.at)
                for task in tasks where task.isOverdue(today: day) {
                    task.day = day
                    task.start = nil
                    changed = true
                }
            }
        }
        WidgetActions.remove(upTo: last)
        return changed
    }

    /// Задачи дня: сначала с временем по порядку, потом без времени.
    private static func dayItems(_ tasks: [PlannerTask], on day: Date, today: Date) -> [WidgetSnapshot.Item] {
        tasks
            .filter { $0.day == day }
            .sorted { a, b in
                if (a.start == nil) != (b.start == nil) { return a.start != nil }
                if let sa = a.start, let sb = b.start, sa != sb { return sa < sb }
                return a.createdAt < b.createdAt
            }
            .map { item($0, today: today, withDay: false) }
    }

    private static func item(_ task: PlannerTask, today: Date, withDay: Bool) -> WidgetSnapshot.Item {
        WidgetSnapshot.Item(
            id: task.id,
            title: task.title,
            start: task.start,
            duration: task.duration,
            isDone: task.isDone,
            colorHex: task.dotHex,
            day: withDay ? task.day : nil,
            isRoutine: task.isRoutine,
            doneToday: task.isDone && task.completedAt.map { DayMath.calendar.startOfDay(for: $0) == today } == true
        )
    }
}

extension PlannerTask {
    /// Цвет точки задачи как число, чтобы передать в виджет.
    var dotHex: UInt32 {
        switch ColorMode.current {
        case .quadrant:
            switch sortedQuadrant {
            case .urgentImportant: return 0xFF6159
            case .important: return 0xFFC53D
            case .urgent: return 0x5E9EFF
            case .other: return 0x5CCB6E
            case nil: return 0x8C8C96
            }
        case .project:
            guard let project else { return 0x8C8C96 }
            return ProjectPalette.colors[((project.colorIndex % ProjectPalette.colors.count) + ProjectPalette.colors.count) % ProjectPalette.colors.count]
        }
    }
}
