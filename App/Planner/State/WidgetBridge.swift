import Foundation
import PlannerCore
import WidgetKit

/// Пишет снимок сегодняшнего дня для виджета и просит WidgetKit перерисоваться.
enum WidgetBridge {
    static func update(_ tasks: [PlannerTask]) {
        let today = DayMath.today()
        let items = tasks
            .filter { $0.day == today }
            .sorted { a, b in
                if (a.start == nil) != (b.start == nil) { return a.start != nil }
                if let sa = a.start, let sb = b.start, sa != sb { return sa < sb }
                return a.createdAt < b.createdAt
            }
            .map { task in
                WidgetSnapshot.Item(
                    id: task.id,
                    title: task.title,
                    start: task.start,
                    duration: task.duration,
                    isDone: task.isDone,
                    colorHex: task.dotHex
                )
            }
        let snapshot = WidgetSnapshot(
            day: today,
            items: items,
            streak: Streak.compute(tasks, today: today).current,
            overdue: tasks.filter { $0.isOverdue(today: today) }.count,
            backlog: tasks.filter { $0.isInBacklog && !$0.isDone }.count
        )
        guard snapshot != WidgetSnapshot.load() else { return }
        do {
            try snapshot.save()
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            // Нет контейнера группы — виджет покажет заглушку, приложение работает как прежде.
        }
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
