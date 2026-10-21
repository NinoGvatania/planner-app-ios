import Foundation
import UserNotifications

/// Локальные уведомления в момент начала задачи.
enum NotificationScheduler {
    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Пересоздаёт уведомления для ближайших задач с временем (не сделанных, в будущем)
    /// и заодно планирует экспорт в Календарь, если он включён.
    static func sync(_ tasks: [PlannerTask]) {
        CalendarSync.schedule(tasks)
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        let now = Date()
        let upcoming = tasks
            .filter { !$0.isDone && $0.day != nil && $0.start != nil }
            .compactMap { task -> (PlannerTask, Date)? in
                guard let day = task.day, let start = task.start else { return nil }
                let date = DayMath.calendar.date(byAdding: .minute, value: start, to: day) ?? day
                return date > now ? (task, date) : nil
            }
            .sorted { $0.1 < $1.1 }
            .prefix(60)
        for (task, date) in upcoming {
            let content = UNMutableNotificationContent()
            content.title = task.title
            content.body = task.project.map { "\($0.name) · " } ?? ""
            content.body += "\(task.duration) мин"
            content.sound = .default
            let components = DayMath.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            center.add(UNNotificationRequest(identifier: task.id.uuidString, content: content, trigger: trigger))
        }
    }
}
