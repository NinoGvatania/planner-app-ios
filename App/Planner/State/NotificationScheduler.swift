import Foundation
import UserNotifications

/// Локальные уведомления к началу задачи (за N минут — настройка «Напоминать»).
enum NotificationScheduler {
    static let leadKey = "reminderLead"
    static let leadOptions: [(minutes: Int, title: String)] = [
        (0, "В момент начала"), (5, "За 5 минут"), (10, "За 10 минут"), (15, "За 15 минут"), (30, "За 30 минут"), (-1, "Не напоминать"),
    ]
    static var lead: Int {
        UserDefaults.standard.object(forKey: leadKey) == nil ? 0 : UserDefaults.standard.integer(forKey: leadKey)
    }
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Пересоздаёт уведомления для ближайших задач с временем (не сделанных, в будущем)
    /// и заодно планирует экспорт в Календарь, если он включён.
    static func sync(_ tasks: [PlannerTask]) {
        CalendarSync.schedule(tasks)
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        let lead = lead
        guard lead >= 0 else { return }
        let now = Date()
        let upcoming = tasks
            .filter { !$0.isDone && $0.day != nil && $0.start != nil }
            .compactMap { task -> (PlannerTask, Date)? in
                guard let day = task.day, let start = task.start else { return nil }
                let date = DayMath.calendar.date(byAdding: .minute, value: start - lead, to: day) ?? day
                return date > now ? (task, date) : nil
            }
            .sorted { $0.1 < $1.1 }
            .prefix(60)
        for (task, date) in upcoming {
            let content = UNMutableNotificationContent()
            content.title = task.title
            content.body = task.project.map { "\($0.name) · " } ?? ""
            content.body += lead > 0 ? "через \(lead) мин, \(task.duration) мин" : "\(task.duration) мин"
            content.sound = .default
            let components = DayMath.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            center.add(UNNotificationRequest(identifier: task.id.uuidString, content: content, trigger: trigger))
        }
    }
}
