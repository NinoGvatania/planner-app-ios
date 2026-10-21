import Foundation
import PlannerCore
import SwiftData

/// Рутины: шаблон `Routine` порождает задачу с `isRoutine = true` на каждый подходящий день
/// ближайшей недели. Включение рутины у задачи создаёт шаблон, выключение — удаляет шаблон
/// и будущие невыполненные копии.
enum RoutineManager {
    /// На сколько дней вперёд создаются копии рутин.
    static let horizon = 7

    /// Досоздать копии рутин на сегодня и неделю вперёд (вызывается при запуске и возврате в приложение).
    static func materialize(in context: ModelContext) {
        guard let routines = try? context.fetch(FetchDescriptor<Routine>()), !routines.isEmpty else { return }
        let today = DayMath.today()
        let horizonEnd = DayMath.day(offset: horizon)
        let existing = (try? context.fetch(FetchDescriptor<PlannerTask>(predicate: #Predicate<PlannerTask> { $0.isRoutine }))) ?? []
        var present = Set(existing.compactMap { task -> String? in
            guard let day = task.day, day >= today, day <= horizonEnd else { return nil }
            return key(title: task.title, day: day)
        })
        for routine in routines {
            for offset in 0...horizon {
                let day = DayMath.day(offset: offset)
                let weekday = DayMath.calendar.component(.weekday, from: day)
                guard routine.weekdays.isEmpty || routine.weekdays.contains(weekday) else { continue }
                let id = key(title: routine.title, day: day)
                guard !present.contains(id) else { continue }
                present.insert(id)
                context.insert(PlannerTask(
                    title: routine.title,
                    day: day,
                    start: routine.start,
                    duration: routine.duration,
                    quadrant: Quadrant(rawValue: routine.quadrantRaw),
                    isRoutine: true
                ))
            }
        }
    }

    /// Задачу сделали рутиной: шаблон по её названию, времени и длительности, копии на неделю.
    static func enable(_ task: PlannerTask, in context: ModelContext) {
        let title = task.title
        let routines = (try? context.fetch(FetchDescriptor<Routine>(predicate: #Predicate<Routine> { $0.title == title }))) ?? []
        if let routine = routines.first {
            routine.start = task.start ?? routine.start
            routine.duration = task.duration
            routine.quadrantRaw = task.quadrantRaw
        } else {
            context.insert(Routine(
                title: title,
                start: task.start ?? 9 * 60,
                duration: task.duration,
                quadrant: Quadrant(rawValue: task.quadrantRaw) ?? .other
            ))
        }
        materialize(in: context)
    }

    /// Рутину выключили: шаблон удаляется вместе с будущими невыполненными копиями.
    static func disable(_ task: PlannerTask, in context: ModelContext) {
        let title = task.title
        let routines = (try? context.fetch(FetchDescriptor<Routine>(predicate: #Predicate<Routine> { $0.title == title }))) ?? []
        for routine in routines { context.delete(routine) }
        let today = DayMath.today()
        let copies = (try? context.fetch(FetchDescriptor<PlannerTask>(
            predicate: #Predicate<PlannerTask> { $0.isRoutine && $0.title == title && !$0.isDone }
        ))) ?? []
        for copy in copies where copy.id != task.id {
            guard let day = copy.day, day >= today else { continue }
            context.delete(copy)
        }
    }

    private static func key(title: String, day: Date) -> String {
        "\(title)|\(day.timeIntervalSinceReferenceDate)"
    }
}
