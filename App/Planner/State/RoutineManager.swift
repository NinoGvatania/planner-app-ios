import Foundation
import PlannerCore
import SwiftData

/// Рутины: шаблон `Routine` порождает задачу с `isRoutine = true` на каждый подходящий день —
/// на неделю вперёд и до конца периода, который сейчас открыт (листаешь месяц вперёд — копии
/// появляются и там). Включение рутины у задачи создаёт шаблон, выключение — удаляет шаблон
/// и будущие невыполненные копии. Шаблон помнит, по какой день копии уже созданы, поэтому
/// удалённая или перенесённая копия не возвращается.
enum RoutineManager {
    /// На сколько дней вперёд копии рутин есть всегда.
    static let horizon = 7
    /// Дальше этого копии не создаются, даже если открыт следующий год.
    static let maxAhead = 400

    /// Досоздать копии рутин на неделю вперёд и до дня `through` включительно (последний день
    /// открытого периода). Вызывается при запуске, возврате в приложение и при листании периодов.
    /// Возвращает созданные задачи.
    @discardableResult
    static func materialize(in context: ModelContext, through: Date? = nil) -> [PlannerTask] {
        guard let routines = try? context.fetch(FetchDescriptor<Routine>()), !routines.isEmpty else { return [] }
        let today = DayMath.today()
        var horizonEnd = DayMath.day(offset: horizon)
        if let through {
            horizonEnd = max(horizonEnd, min(DayMath.calendar.startOfDay(for: through), DayMath.day(offset: maxAhead)))
        }
        let existing = (try? context.fetch(FetchDescriptor<PlannerTask>(predicate: #Predicate<PlannerTask> { $0.isRoutine }))) ?? []
        var present = Set(existing.compactMap { task -> String? in
            guard let day = task.day, day >= today, day <= horizonEnd else { return nil }
            return key(title: task.title, day: day)
        })
        let projects = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        var created: [PlannerTask] = []
        for routine in routines {
            let firstDay = routine.materializedThrough.map { DayMath.day(offset: DayMath.offset(of: $0) + 1) } ?? today
            var day = max(today, firstDay)
            while day <= horizonEnd {
                defer { day = DayMath.calendar.date(byAdding: .day, value: 1, to: day) ?? horizonEnd.addingTimeInterval(1) }
                guard matches(routine, day: day) else { continue }
                let id = key(title: routine.title, day: day)
                guard !present.contains(id) else { continue }
                present.insert(id)
                let task = PlannerTask(
                    title: routine.title,
                    day: day,
                    start: routine.start,
                    duration: routine.duration,
                    quadrant: Quadrant(rawValue: routine.quadrantRaw),
                    isRoutine: true,
                    project: routine.projectName.flatMap { name in projects.first { $0.name == name } }
                )
                context.insert(task)
                created.append(task)
            }
            // Только вперёд: вернулись к текущей неделе после следующего года — уже созданное не пересоздаётся.
            if routine.materializedThrough.map({ $0 < horizonEnd }) ?? true {
                routine.materializedThrough = horizonEnd
            }
        }
        return created
    }

    /// Задачу сделали рутиной: шаблон по её названию, времени и длительности, копии на неделю.
    /// Задача из бэклога переезжает на сегодня — она и есть сегодняшняя копия.
    static func enable(_ task: PlannerTask, in context: ModelContext) {
        let title = task.title
        let routines = (try? context.fetch(FetchDescriptor<Routine>(predicate: #Predicate<Routine> { $0.title == title }))) ?? []
        let start = task.start ?? 9 * 60
        if let routine = routines.first {
            routine.start = start
            routine.duration = task.duration
            routine.quadrantRaw = task.quadrantRaw
            routine.projectName = task.project?.name
            routine.materializedThrough = nil
        } else {
            context.insert(Routine(
                title: title,
                start: start,
                duration: task.duration,
                quadrant: Quadrant(rawValue: task.quadrantRaw) ?? .other,
                projectName: task.project?.name
            ))
        }
        if task.day == nil {
            task.day = DayMath.today()
            task.start = start
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

    /// Подходит ли день под расписание рутины: дни недели и чётность недели года.
    static func matches(_ routine: Routine, day: Date) -> Bool {
        let weekday = DayMath.calendar.component(.weekday, from: day)
        guard routine.weekdays.isEmpty || routine.weekdays.contains(weekday) else { return false }
        guard routine.weekParity != 0 else { return true }
        let week = DayMath.calendar.component(.weekOfYear, from: day)
        return routine.weekParity == 1 ? week % 2 == 1 : week % 2 == 0
    }

    /// Расписание изменили: будущие невыполненные копии пересоздаются по новым правилам.
    /// `kept` — задача, которую сейчас редактируют: она остаётся как есть.
    static func regenerate(_ routine: Routine, keeping kept: PlannerTask?, in context: ModelContext) {
        let title = routine.title
        let today = DayMath.today()
        let copies = (try? context.fetch(FetchDescriptor<PlannerTask>(
            predicate: #Predicate<PlannerTask> { $0.isRoutine && $0.title == title && !$0.isDone }
        ))) ?? []
        for copy in copies where copy.id != kept?.id {
            guard let day = copy.day, day >= today else { continue }
            context.delete(copy)
        }
        // Редактируемая копия остаётся как есть, даже если её день больше не подходит под расписание.
        routine.materializedThrough = nil
        materialize(in: context)
    }

    private static func key(title: String, day: Date) -> String {
        "\(title)|\(day.timeIntervalSinceReferenceDate)"
    }
}
