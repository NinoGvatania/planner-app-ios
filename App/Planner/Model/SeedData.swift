import Foundation
import PlannerCore
import SwiftData

/// Демонстрационные данные — те же, что в прототипе, относительно сегодняшнего дня.
enum SeedData {
    private static let colorsAssignedKey = "projectColorsAssigned"
    private static let seedColors: [String: Int] = ["Учёба": 0, "Дом": 2, "Спорт": 3, "Рутины": 4]

    /// Одноразово раздать цвета проектам, созданным до появления `colorIndex` (у них всех 0).
    static func assignProjectColorsIfNeeded(in context: ModelContext) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: colorsAssignedKey) else { return }
        defaults.set(true, forKey: colorsAssignedKey)
        let projects = (try? context.fetch(FetchDescriptor<Project>(sortBy: [SortDescriptor(\.name)]))) ?? []
        for (index, project) in projects.enumerated() {
            project.colorIndex = seedColors[project.name] ?? index % ProjectPalette.colors.count
        }
    }

    static func seedIfNeeded(in context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<PlannerTask>())) ?? 0
        guard count == 0 else { return }
        UserDefaults.standard.set(true, forKey: colorsAssignedKey)

        let study = Project(name: "Учёба", colorIndex: 0)
        let home = Project(name: "Дом", colorIndex: 2)
        let sport = Project(name: "Спорт", colorIndex: 3)
        let routines = Project(name: "Рутины", colorIndex: 4)
        for project in [study, home, sport, routines] {
            context.insert(project)
        }

        func h(_ hour: Int, _ minute: Int = 0) -> Int { hour * 60 + minute }
        func day(_ offset: Int) -> Date { DayMath.day(offset: offset) }

        var rank = 0
        func task(
            _ title: String, day dayOffset: Int?, start: Int?, duration: Int, quadrant: Quadrant?,
            done: Bool = false, routine: Bool = false, project: Project? = nil
        ) {
            rank += 1
            let item = PlannerTask(
                title: title,
                day: dayOffset.map { day($0) },
                start: start,
                duration: duration,
                quadrant: quadrant,
                isDone: done,
                isRoutine: routine,
                project: project,
                backlogRank: rank
            )
            context.insert(item)
        }

        task("Умыться и почистить зубы", day: 0, start: h(8), duration: 30, quadrant: .urgent, done: true, routine: true, project: routines)
        task("Завтрак", day: 0, start: h(8, 30), duration: 30, quadrant: .urgent, done: true, routine: true, project: routines)
        task("Созвон по практике", day: 0, start: h(10), duration: 30, quadrant: .urgentImportant, done: true, project: study)
        task("Придумать контент для Threads по AI", day: 0, start: h(12, 15), duration: 60, quadrant: .urgent)
        task("Писать главу диплома", day: 0, start: h(14, 30), duration: 90, quadrant: .urgentImportant, project: study)
        task("Тренировка", day: 0, start: h(18, 30), duration: 60, quadrant: .important, project: sport)
        task("Полить цветы", day: 0, start: nil, duration: 15, quadrant: .other, project: home)
        task("Созвон с научным руководителем", day: 1, start: h(11), duration: 30, quadrant: .urgentImportant, project: study)
        task("Сдать отчёт по практике", day: 1, start: nil, duration: 30, quadrant: .urgentImportant, project: study)
        task("Забрать посылку", day: 1, start: h(17), duration: 30, quadrant: .urgent)
        task("Спортзал", day: 2, start: h(19), duration: 60, quadrant: .important, project: sport)
        task("Подготовить презентацию", day: 3, start: h(10), duration: 120, quadrant: .important, project: study)
        task("Поездка за город", day: 5, start: nil, duration: 30, quadrant: .other)
        task("Позвонить насчёт свидетельства из автошколы", day: -1, start: h(10, 30), duration: 30, quadrant: .urgent)
        task("Написать руководителю практики про задолженность", day: -2, start: h(11), duration: 30, quadrant: .urgentImportant, project: study)
        task("Оплатить интернет", day: -3, start: nil, duration: 15, quadrant: .urgent, project: home)
        task("Купить продукты на неделю", day: nil, start: nil, duration: 45, quadrant: .urgent, project: home)
        task("Сделать бэкап фото", day: nil, start: nil, duration: 30, quadrant: nil)
        task("Разобрать почту", day: nil, start: nil, duration: 30, quadrant: .other)
        task("Почитать про SwiftUI", day: nil, start: nil, duration: 60, quadrant: .important, project: study)
        task("Обновить резюме", day: nil, start: nil, duration: 60, quadrant: .important)
        task("Записаться к стоматологу", day: nil, start: nil, duration: 15, quadrant: .urgentImportant)

        context.insert(Routine(title: "Умыться и почистить зубы", start: h(8), duration: 30, quadrant: .urgent, projectName: "Рутины"))
        context.insert(Routine(title: "Завтрак", start: h(8, 30), duration: 30, quadrant: .urgent, projectName: "Рутины"))
    }
}
