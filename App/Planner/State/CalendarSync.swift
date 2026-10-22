import EventKit
import Foundation
import UIKit

/// Экспорт задач в Календарь (EventKit). Свой календарь «Quick» в источнике по умолчанию (iCloud/локально)
/// или любой календарь на выбор — в том числе Google-аккаунта, подключённого в iOS. Задачи с временем —
/// события, без времени — на весь день; сделанные и бэклог в календарь не попадают. Свои события
/// помечены ссылкой `quick://task/<id>`: чужие события календаря не трогаем.
enum CalendarSync {
    static let enabledKey = "calendarExport"
    static let calendarKey = "calendarExportCalendarID"
    static let autoCalendarTitle = "Quick"

    static let store = EKEventStore()
    private static var pending: Task<Void, Never>?

    /// Снимок задачи, безопасный для фоновой работы.
    struct Item: Sendable {
        let id: UUID
        let title: String
        let day: Date
        let start: Int?
        let duration: Int
        let project: String?
        let notes: String
    }

    struct CalendarChoice: Identifiable, Hashable {
        let id: String
        let title: String
        let source: String
    }

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
    static var hasAccess: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }
    static var isDenied: Bool {
        let status = EKEventStore.authorizationStatus(for: .event)
        return status == .denied || status == .restricted || status == .writeOnly
    }

    static func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    /// Календари, куда можно писать, сгруппированные по источнику (iCloud, Google, локально).
    static func writableCalendars() -> [CalendarChoice] {
        store.calendars(for: .event)
            .filter { $0.allowsContentModifications }
            .map { CalendarChoice(id: $0.calendarIdentifier, title: $0.title, source: $0.source?.title ?? "") }
            .sorted { a, b in
                if a.source != b.source { return a.source < b.source }
                return a.title < b.title
            }
    }

    /// Запланировать синхронизацию с задержкой: жесты дёргают её часто, календарю хватит одного раза.
    static func schedule(_ tasks: [PlannerTask]) {
        guard isEnabled, hasAccess else { return }
        let items = snapshot(tasks)
        pending?.cancel()
        pending = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            sync(items)
        }
    }

    /// Синхронизировать прямо сейчас (кнопка в настройках). Возвращает число своих событий в календаре,
    /// `nil` — календарь недоступен (не удалось создать «Quick»).
    /// Снимок задач делается на главном акторе (модели SwiftData), в фоне — только работа с календарём.
    @MainActor
    static func syncNow(_ tasks: [PlannerTask]) async -> Int? {
        let items = snapshot(tasks)
        pending?.cancel()
        return await Task.detached(priority: .userInitiated) { sync(items) }.value
    }

    /// Экспорт выключили: убрать свои события из календаря (чужие не трогаем).
    static func clear() async {
        pending?.cancel()
        _ = await Task.detached(priority: .userInitiated) {
            sync([])
        }.value
    }

    static func snapshot(_ tasks: [PlannerTask]) -> [Item] {
        tasks.compactMap { task in
            guard let day = task.day, !task.isDone else { return nil }
            return Item(id: task.id, title: task.title, day: day, start: task.start, duration: task.duration,
                        project: task.project?.name, notes: task.notes)
        }
    }

    // MARK: - Календарь

    /// Выбранный календарь, иначе «Quick» (ищется по названию, при необходимости создаётся).
    static func targetCalendar(createIfNeeded: Bool) -> EKCalendar? {
        let defaults = UserDefaults.standard
        if let id = defaults.string(forKey: calendarKey), !id.isEmpty,
           let chosen = store.calendar(withIdentifier: id), chosen.allowsContentModifications {
            return chosen
        }
        if let existing = store.calendars(for: .event).first(where: { $0.title == autoCalendarTitle && $0.allowsContentModifications }) {
            return existing
        }
        guard createIfNeeded else { return nil }
        // Google/Exchange через CalDAV новые календари не принимают: пробуем источники по очереди.
        let sources = store.sources
        var candidates: [EKSource] = []
        func add(_ source: EKSource?) {
            guard let source, !candidates.contains(where: { $0.sourceIdentifier == source.sourceIdentifier }) else { return }
            candidates.append(source)
        }
        add(sources.first { $0.sourceType == .calDAV && $0.title.localizedCaseInsensitiveContains("icloud") })
        add(store.defaultCalendarForNewEvents?.source)
        add(sources.first { $0.sourceType == .local })
        sources.forEach { add($0) }
        for source in candidates {
            let calendar = EKCalendar(for: .event, eventStore: store)
            calendar.title = autoCalendarTitle
            calendar.cgColor = UIColor(red: 0x3E / 255, green: 0xE0 / 255, blue: 0xA6 / 255, alpha: 1).cgColor
            calendar.source = source
            if (try? store.saveCalendar(calendar, commit: true)) != nil {
                return calendar
            }
        }
        return nil
    }

    // MARK: - Синхронизация

    private static func marker(_ id: UUID) -> URL? { URL(string: "quick://task/\(id.uuidString)") }

    private static func taskID(of event: EKEvent) -> String? {
        guard let url = event.url, url.scheme == "quick", url.host == "task" else { return nil }
        let id = url.lastPathComponent
        return id.isEmpty ? nil : id
    }

    @discardableResult
    static func sync(_ items: [Item]) -> Int? {
        guard let calendar = targetCalendar(createIfNeeded: !items.isEmpty) else { return items.isEmpty ? 0 : nil }
        // Окно поиска: год назад и год вперёд, но так, чтобы покрыть все экспортируемые даты.
        let now = Date()
        var start = now.addingTimeInterval(-370 * 86_400)
        var end = now.addingTimeInterval(400 * 86_400)
        if let earliest = items.map(\.day).min() { start = min(start, earliest.addingTimeInterval(-2 * 86_400)) }
        if let latest = items.map(\.day).max() { end = max(end, latest.addingTimeInterval(3 * 86_400)) }
        // Свои события ищем во всех календарях: после смены календаря в настройках старые переезжают.
        let window = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        var existing: [String: EKEvent] = [:]
        for event in store.events(matching: window) {
            if let id = taskID(of: event) { existing[id] = event }
        }
        var seen = Set<String>()
        var dirty = false
        for item in items {
            let key = item.id.uuidString
            seen.insert(key)
            if let event = existing[key] {
                guard apply(item, to: event, in: calendar) else { continue }
                do {
                    try store.save(event, span: .thisEvent, commit: false)
                    dirty = true
                } catch {
                    // Перенос между источниками (iCloud → Google) не удался: удалить и создать заново.
                    if (try? store.remove(event, span: .thisEvent, commit: false)) != nil { dirty = true }
                    let fresh = EKEvent(eventStore: store)
                    _ = apply(item, to: fresh, in: calendar)
                    if (try? store.save(fresh, span: .thisEvent, commit: false)) != nil { dirty = true }
                }
            } else {
                let event = EKEvent(eventStore: store)
                _ = apply(item, to: event, in: calendar)
                if (try? store.save(event, span: .thisEvent, commit: false)) != nil { dirty = true }
            }
        }
        for (key, event) in existing where !seen.contains(key) {
            if (try? store.remove(event, span: .thisEvent, commit: false)) != nil { dirty = true }
        }
        if dirty { try? store.commit() }
        return seen.count
    }

    /// Переписать событие по задаче. Возвращает `true`, если что-то изменилось.
    private static func apply(_ item: Item, to event: EKEvent, in calendar: EKCalendar) -> Bool {
        let cal = DayMath.calendar
        let startDate: Date
        let endDate: Date
        let allDay: Bool
        if let start = item.start {
            allDay = false
            startDate = cal.date(byAdding: .minute, value: start, to: item.day) ?? item.day
            endDate = cal.date(byAdding: .minute, value: start + item.duration, to: item.day) ?? startDate
        } else {
            allDay = true
            startDate = item.day
            endDate = (cal.date(byAdding: .day, value: 1, to: item.day) ?? item.day).addingTimeInterval(-1)
        }
        // Заметка задачи и проект — в заметке события.
        let parts = [item.notes.trimmingCharacters(in: .whitespacesAndNewlines), item.project.map { "Проект: \($0)" } ?? ""]
            .filter { !$0.isEmpty }
        let notes: String? = parts.isEmpty ? nil : parts.joined(separator: "\n")
        let marker = marker(item.id)
        let unchanged = event.calendar == calendar
            && event.title == item.title
            && event.isAllDay == allDay
            && event.startDate == startDate
            && event.endDate == endDate
            && event.notes == notes
            && event.url == marker
        guard !unchanged else { return false }
        event.calendar = calendar
        event.title = item.title
        event.isAllDay = allDay
        event.startDate = startDate
        event.endDate = endDate
        event.notes = notes
        event.url = marker
        return true
    }
}
