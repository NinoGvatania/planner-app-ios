import AppIntents
import PlannerCore
import UserNotifications
import WidgetKit

/// Галочка в виджете. Виджет не видит базу приложения, поэтому задача сразу отмечается в снимке
/// (виджет перерисуется уже с ней), а в базу попадёт из очереди, когда приложение откроют.
struct ToggleTaskIntent: AppIntent {
    static var title: LocalizedStringResource { "Отметить задачу" }
    static var isDiscoverable: Bool { false }

    @Parameter(title: "Задача")
    var taskID: String

    init() {}

    init(id: UUID) {
        taskID = id.uuidString
    }

    func perform() async throws -> some IntentResult {
        let now = Date()
        guard let id = UUID(uuidString: taskID),
              let snapshot = WidgetSnapshot.load()?.rolled(to: now)
        else { return .result() }
        // Задача дня или просроченная; закрытая просроченная скрывается, но второй галочкой («вернуть») открывается.
        let known = snapshot.items + (snapshot.overdueItems ?? [])
        guard known.contains(where: { $0.id == id }) else { return .result() }
        let updated = snapshot.toggling(id, at: now)
        let done = updated.isDone(id)
        try? updated.save()
        try? WidgetActions.append(.setDone(id, done, at: now))
        // Сделанной задаче напоминание уже ни к чему; снятую галочку приложение вернёт при следующей синхронизации.
        if done {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id.uuidString])
        }
        return .result()
    }
}

/// «На сегодня» в виджете: все просроченные — на сегодня, на весь день (как в листе «Просрочено»).
struct MoveOverdueToTodayIntent: AppIntent {
    static var title: LocalizedStringResource { "Просроченные — на сегодня" }
    static var isDiscoverable: Bool { false }

    init() {}

    func perform() async throws -> some IntentResult {
        let now = Date()
        guard let snapshot = WidgetSnapshot.load()?.rolled(to: now), snapshot.overdue > 0 else { return .result() }
        try? snapshot.movingOverdueToToday().save()
        try? WidgetActions.append(.overdueToToday(at: now))
        return .result()
    }
}
