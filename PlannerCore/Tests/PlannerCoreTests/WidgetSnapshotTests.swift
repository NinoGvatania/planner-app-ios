import Foundation
import XCTest
@testable import PlannerCore

final class WidgetSnapshotTests: XCTestCase {
    /// Пятница, 15 января 2027, 8:00 UTC.
    private let day = Date(timeIntervalSince1970: 1_800_000_000)

    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func item(_ title: String, start: Int?, duration: Int = 60, done: Bool = false) -> WidgetSnapshot.Item {
        WidgetSnapshot.Item(id: UUID(), title: title, start: start, duration: duration, isDone: done, colorHex: 0)
    }

    func testTimingAndAgenda() {
        let missed = item("Утро", start: 8 * 60, duration: 30)
        let now = item("Созвон", start: 11 * 60)
        let later = item("Обед", start: 13 * 60)
        let allDay = item("Весь день", start: nil)
        let done = item("Сделано", start: 10 * 60, done: true)
        let snapshot = WidgetSnapshot(day: day, items: [missed, done, now, later, allDay], streak: 3, overdue: 0, backlog: 0)
        let at = 11 * 60 + 20
        XCTAssertEqual(snapshot.timing(of: now, at: at), .now(minutesLeft: 40))
        XCTAssertEqual(snapshot.timing(of: later, at: at), .later(minutes: 100))
        XCTAssertEqual(snapshot.timing(of: missed, at: at), .missed(minutesAgo: 170))
        XCTAssertEqual(snapshot.timing(of: allDay, at: at), .allDay)
        XCTAssertEqual(snapshot.timing(of: done, at: at), .done)
        // Сначала идущая, потом предстоящая, без времени, пропущенная; сделанной нет.
        XCTAssertEqual(snapshot.agenda(at: at).map(\.title), ["Созвон", "Обед", "Весь день", "Утро"])
        XCTAssertEqual(snapshot.progress, 0.2, accuracy: 0.001)
        XCTAssertEqual(snapshot.nextTimed(after: at)?.title, "Обед")
    }

    func testJustEndedComesFirstWhileNothingRuns() {
        let call = item("Созвон", start: 11 * 60)
        let lunch = item("Обед", start: 13 * 60)
        let walk = item("Прогулка", start: 12 * 60 + 5, duration: 30)
        let allDay = item("Весь день", start: nil)
        let snapshot = WidgetSnapshot(day: day, items: [call, walk, lunch, allDay], streak: 0, overdue: 0, backlog: 0)
        // 12:03: созвон кончился 3 минуты назад, прогулка ещё не началась — спросить про созвон.
        XCTAssertEqual(snapshot.agenda(at: 12 * 60 + 3).map(\.title), ["Созвон", "Прогулка", "Обед", "Весь день"])
        // 12:10: идёт прогулка — кончившийся созвон уходит в конец.
        XCTAssertEqual(snapshot.agenda(at: 12 * 60 + 10).map(\.title), ["Прогулка", "Обед", "Весь день", "Созвон"])
        // 12:45: прогулка кончилась только что — спросить про неё; созвон прошёл давно.
        XCTAssertEqual(snapshot.agenda(at: 12 * 60 + 45).map(\.title), ["Прогулка", "Обед", "Весь день", "Созвон"])
        // 15:00: все давно прошли — в конце, свежая первой.
        XCTAssertEqual(snapshot.agenda(at: 15 * 60).map(\.title), ["Весь день", "Обед", "Прогулка", "Созвон"])
    }

    func testOverdueTimingAndTimelineBounds() {
        let yesterday = day.addingTimeInterval(-86_400)
        let old = WidgetSnapshot.Item(id: UUID(), title: "Старая", start: 9 * 60, duration: 30, isDone: false,
                                      colorHex: 0, day: yesterday)
        let late = item("Поздно", start: 22 * 60 + 30, duration: 60)
        let snapshot = WidgetSnapshot(day: day, items: [late], streak: 0, overdue: 1, backlog: 0, overdueItems: [old])
        XCTAssertEqual(snapshot.timing(of: old, at: 600), .overdue(yesterday))
        XCTAssertEqual(snapshot.timelineBounds(at: 7 * 60 + 10), 7 * 60...24 * 60)
        XCTAssertEqual(WidgetSnapshot(day: day, items: [], streak: 0, overdue: 0, backlog: 0).timelineBounds(at: 600),
                       8 * 60...22 * 60)
    }

    func testTogglingTodayAndOverdue() {
        let a = item("Сегодня", start: 9 * 60)
        let old = item("Вчера", start: 9 * 60)
        let snapshot = WidgetSnapshot(day: day, items: [a], streak: 2, overdue: 1, backlog: 0,
                                      overdueItems: [old], streakBefore: 2, doneElsewhere: 0)
        let checked = snapshot.toggling(a.id, at: day)
        XCTAssertTrue(checked.isDone(a.id))
        XCTAssertEqual(checked.displayStreak, 3)
        XCTAssertEqual(checked.lastDone, .setDone(a.id, true, at: day))
        let unchecked = checked.toggling(a.id)
        XCTAssertFalse(unchecked.isDone(a.id))
        XCTAssertNil(unchecked.lastDone)
        // Закрытая просроченная скрыта, но идёт в серию и возвращается второй галочкой.
        let cleared = snapshot.toggling(old.id, at: day)
        XCTAssertEqual(cleared.overdue, 0)
        XCTAssertEqual(cleared.openOverdue.count, 0)
        XCTAssertTrue(cleared.isDone(old.id))
        XCTAssertEqual(cleared.displayStreak, 3)
        XCTAssertEqual(cleared.justDone(at: day.addingTimeInterval(30))?.id, old.id)
        XCTAssertNil(cleared.justDone(at: day.addingTimeInterval(WidgetSnapshot.undoWindow + 1)))
        let restored = cleared.toggling(old.id)
        XCTAssertEqual(restored.overdue, 1)
        XCTAssertEqual(restored.openOverdue.map(\.id), [old.id])
        XCTAssertEqual(restored.displayStreak, 2)
        // Чужой id ничего не меняет.
        XCTAssertNil(snapshot.toggling(UUID()).lastDone)
    }

    func testStreakAtRiskInTheEvening() {
        let snapshot = WidgetSnapshot(day: day, items: [item("Дело", start: nil)], streak: 3, overdue: 0, backlog: 0,
                                      streakBefore: 3, doneElsewhere: 0)
        XCTAssertFalse(snapshot.streakAtRisk(at: 17 * 60 + 59))
        XCTAssertTrue(snapshot.streakAtRisk(at: 18 * 60))
        XCTAssertFalse(snapshot.toggling(snapshot.items[0].id).streakAtRisk(at: 21 * 60))
        XCTAssertFalse(WidgetSnapshot(day: day, items: [], streak: 0, overdue: 0, backlog: 0).streakAtRisk(at: 21 * 60))
    }

    func testTimelineDates() {
        let calendar = utc
        let today = calendar.startOfDay(for: day)
        let now = today.addingTimeInterval(10 * 3600 + 30)  // 10:00:30
        let meeting = item("Встреча", start: 15 * 60, duration: 30)
        let snapshot = WidgetSnapshot(day: today, items: [meeting], streak: 0, overdue: 0, backlog: 0)
        let dates = snapshot.timelineDates(from: now, calendar: calendar)
        XCTAssertEqual(dates.first, now)
        XCTAssertEqual(dates, dates.sorted())
        XCTAssertLessThanOrEqual(dates.count, 200)
        XCTAssertTrue(dates.contains(today.addingTimeInterval(10 * 3600 + 60)), "каждая минута первого часа")
        XCTAssertTrue(dates.contains(today.addingTimeInterval(15 * 3600)), "начало встречи")
        XCTAssertTrue(dates.contains(today.addingTimeInterval(15.5 * 3600)), "конец встречи")
        XCTAssertTrue(dates.contains(today.addingTimeInterval(18 * 3600)), "вечерний час серии")
        XCTAssertEqual(dates.last, today.addingTimeInterval(86_400 + 1), "сразу после полуночи")
        // Без задач с временем — реже.
        let quiet = WidgetSnapshot(day: today, items: [item("Почитать", start: nil)], streak: 0, overdue: 0, backlog: 0)
        XCTAssertFalse(quiet.timelineDates(from: now, calendar: calendar).contains(today.addingTimeInterval(10 * 3600 + 60)))
    }

    func testMovingOverdueToToday() {
        let a = item("Сегодня", start: 9 * 60)
        var old = item("Вчера", start: 10 * 60)
        old.day = day.addingTimeInterval(-86_400)
        let snapshot = WidgetSnapshot(day: day, items: [a], streak: 0, overdue: 3, backlog: 0, overdueItems: [old])
        let moved = snapshot.movingOverdueToToday()
        XCTAssertEqual(moved.items.map(\.title), ["Сегодня", "Вчера"])
        XCTAssertNil(moved.items.last?.start)
        XCTAssertNil(moved.items.last?.day)
        XCTAssertEqual(moved.timing(of: moved.items[1], at: 600), .allDay)
        // Не все просроченные были в снимке, но приложение перенесёт и остальные.
        XCTAssertEqual(moved.overdue, 0)
        XCTAssertEqual(moved.overdueItems?.count, 0)
    }

    func testStreakCountsOnlyWhatIsDoneToday() {
        // Сделана раньше срока, в прошлый день: в серию за сегодня не идёт.
        var early = item("Заранее", start: nil, done: true)
        early.doneToday = false
        let open = item("Дело", start: nil)
        let snapshot = WidgetSnapshot(day: day, items: [early, open], streak: 4, overdue: 0, backlog: 0,
                                      streakBefore: 4, doneElsewhere: 0)
        XCTAssertFalse(snapshot.isTodayClosed)
        XCTAssertEqual(snapshot.displayStreak, 4)
        XCTAssertTrue(snapshot.streakAtRisk(at: 20 * 60))
        // Сделано сегодня из бэклога — день закрыт, хотя в списках снимка галочек нет.
        let elsewhere = WidgetSnapshot(day: day, items: [open], streak: 5, overdue: 0, backlog: 0,
                                       streakBefore: 4, doneElsewhere: 1)
        XCTAssertTrue(elsewhere.isTodayClosed)
        XCTAssertEqual(elsewhere.displayStreak, 5)
    }

    func testUncheckingTheOnlyDoneTaskReopensTheDay() {
        var done = item("Сделал", start: nil, done: true)
        done.doneToday = true
        let snapshot = WidgetSnapshot(day: day, items: [done], streak: 5, overdue: 0, backlog: 0,
                                      streakBefore: 4, doneElsewhere: 0)
        XCTAssertEqual(snapshot.displayStreak, 5)
        let reopened = snapshot.toggling(done.id)
        XCTAssertFalse(reopened.isTodayClosed)
        XCTAssertEqual(reopened.displayStreak, 4)
        XCTAssertTrue(reopened.streakAtRisk(at: 19 * 60))
        // Снова отметил — день закрыт.
        XCTAssertEqual(reopened.toggling(done.id).displayStreak, 5)
    }

    func testOldSnapshotWithoutStreakBefore() {
        let a = item("Сегодня", start: nil, done: true)
        let snapshot = WidgetSnapshot(day: day, items: [a], streak: 5, overdue: 0, backlog: 0)
        XCTAssertTrue(snapshot.isTodayClosed)
        XCTAssertEqual(snapshot.displayStreak, 5)
    }

    func testWeekFollowsTodayInWidget() {
        let today = utc.startOfDay(for: day)
        let a = item("Сегодня", start: nil)
        let week = [true, true, false, true, false, false, false]
        let snapshot = WidgetSnapshot(day: today, items: [a], streak: 1, overdue: 0, backlog: 0,
                                      streakBefore: 1, doneElsewhere: 0, week: week)
        XCTAssertEqual(WidgetSnapshot.weekIndex(of: today, calendar: utc), 4)
        XCTAssertEqual(snapshot.displayWeek(calendar: utc), week)
        let checked = snapshot.toggling(a.id)
        XCTAssertEqual(checked.displayWeek(calendar: utc), [true, true, false, true, true, false, false])
        XCTAssertEqual(checked.toggling(a.id).displayWeek(calendar: utc), week)
    }

    func testFocusFillsFreeTimeWithTaskWithoutTime() {
        let meeting = item("Встреча", start: 15 * 60)
        let read = item("Почитать", start: nil)
        let snapshot = WidgetSnapshot(day: day, items: [meeting, read], streak: 0, overdue: 0, backlog: 0)
        // До встречи пять часов — свободное время: главная — задача без времени.
        XCTAssertEqual(snapshot.focus(at: 10 * 60)?.title, "Почитать")
        // До встречи меньше часа — она главная.
        XCTAssertEqual(snapshot.focus(at: 14 * 60 + 10)?.title, "Встреча")
        XCTAssertEqual(snapshot.focus(at: 15 * 60 + 10)?.title, "Встреча")
        // Без задач без времени — встреча, даже если до неё далеко.
        XCTAssertEqual(WidgetSnapshot(day: day, items: [meeting], streak: 0, overdue: 0, backlog: 0).focus(at: 9 * 60)?.title,
                       "Встреча")
        XCTAssertNil(WidgetSnapshot(day: day, items: [], streak: 0, overdue: 0, backlog: 0).focus(at: 600))
    }

    func testActionsAppliedInOrder() {
        let id = UUID()
        let actions = [
            WidgetAction.setDone(id, false, at: day.addingTimeInterval(5)),
            WidgetAction.overdueToToday(at: day.addingTimeInterval(1)),
            WidgetAction.setDone(id, true, at: day),
        ]
        let ordered = WidgetActions.ordered(actions)
        XCTAssertEqual(ordered.map(\.kind), [.setDone, .overdueToToday, .setDone])
        XCTAssertEqual(ordered.last?.done, false)
    }

    func testOldSnapshotJSONStillDecodes() throws {
        let json = """
        {"day":"2027-01-15T00:00:00Z","items":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","title":"А","duration":30,"isDone":false,"colorHex":0}],
         "streak":1,"overdue":0,"backlog":2,"generatedAt":"2027-01-15T08:00:00Z"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(WidgetSnapshot.self, from: Data(json.utf8))
        XCTAssertNil(snapshot.overdueItems)
        XCTAssertNil(snapshot.items.first?.day)
        XCTAssertNil(snapshot.lastDone)
        XCTAssertNil(snapshot.displayWeek())
        XCTAssertEqual(snapshot.displayStreak, 1)
    }

    func testRollsOverToNextDay() {
        let calendar = utc
        let today = calendar.startOfDay(for: day)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let open = item("Не успел", start: 9 * 60)
        let next = item("Завтрашняя", start: 10 * 60)
        var done = item("Сделал", start: nil, done: true)
        done.doneToday = true
        var early = item("Завтрашняя заранее", start: nil, done: true)
        early.doneToday = true
        let snapshot = WidgetSnapshot(day: today, items: [open, done], streak: 4, overdue: 1, backlog: 0,
                                      overdueItems: [item("Старая", start: nil)], tomorrowItems: [next, early],
                                      streakBefore: 3, doneElsewhere: 0,
                                      bestStreak: 3, week: [true, true, true, true, true, false, false])
        XCTAssertEqual(snapshot.rolled(to: today, calendar: calendar)?.items.count, 2)
        let rolled = snapshot.rolled(to: tomorrow.addingTimeInterval(3600), calendar: calendar)
        XCTAssertEqual(rolled?.day, tomorrow)
        XCTAssertEqual(rolled?.items.map(\.title), ["Завтрашняя", "Завтрашняя заранее"])
        XCTAssertEqual(rolled?.overdue, 2)
        XCTAssertEqual(rolled?.overdueItems?.map(\.title), ["Старая", "Не успел"])
        XCTAssertEqual(rolled?.overdueItems?.last?.day, today)
        XCTAssertEqual(rolled?.streak, 4)
        XCTAssertEqual(rolled?.streakBefore, 4)
        XCTAssertEqual(rolled?.bestStreak, 4)
        // Сделанная заранее не закрывает новый день.
        XCTAssertEqual(rolled?.isTodayClosed, false)
        XCTAssertEqual(rolled?.displayStreak, 4)
        XCTAssertEqual(rolled?.week, [true, true, true, true, true, false, false])
        XCTAssertNil(snapshot.rolled(to: calendar.date(byAdding: .day, value: 2, to: today)!, calendar: calendar))
    }

    func testRolloverBreaksStreakWhenNothingDone() {
        let calendar = utc
        let today = calendar.startOfDay(for: day)
        let routine = WidgetSnapshot.Item(id: UUID(), title: "Зарядка", start: 8 * 60, duration: 15, isDone: false,
                                          colorHex: 0, isRoutine: true)
        let snapshot = WidgetSnapshot(day: today, items: [item("Не успел", start: nil), routine], streak: 4, overdue: 0,
                                      backlog: 0, tomorrowItems: [], streakBefore: 4, doneElsewhere: 0)
        let rolled = snapshot.rolled(to: calendar.date(byAdding: .day, value: 1, to: today)!, calendar: calendar)
        XCTAssertEqual(rolled?.streak, 0)
        XCTAssertEqual(rolled?.items.count, 0)
        // Рутина не становится просроченной.
        XCTAssertEqual(rolled?.overdueItems?.map(\.title), ["Не успел"])
    }

    func testRolloverIntoMondayClearsWeek() {
        let calendar = utc
        let sunday = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: day))!
        var done = item("Сделал", start: nil, done: true)
        done.doneToday = true
        let snapshot = WidgetSnapshot(day: sunday, items: [done], streak: 6, overdue: 0, backlog: 0, tomorrowItems: [],
                                      streakBefore: 5, doneElsewhere: 0, week: Array(repeating: true, count: 7))
        let monday = calendar.date(byAdding: .day, value: 1, to: sunday)!
        XCTAssertEqual(WidgetSnapshot.weekIndex(of: monday, calendar: calendar), 0)
        XCTAssertEqual(snapshot.rolled(to: monday, calendar: calendar)?.week, Array(repeating: false, count: 7))
    }

    func testRolledSnapshotDoesNotRollAgain() {
        let calendar = utc
        let today = calendar.startOfDay(for: day)
        let snapshot = WidgetSnapshot(day: today, items: [], streak: 0, overdue: 0, backlog: 0,
                                      tomorrowItems: [item("Завтра", start: nil)], streakBefore: 0, doneElsewhere: 0)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        guard let rolled = snapshot.rolled(to: tomorrow, calendar: calendar) else { return XCTFail("должен перевернуться") }
        // Послезавтра неизвестно — показывать нечего, а не «пустой день».
        XCTAssertNil(rolled.rolled(to: calendar.date(byAdding: .day, value: 1, to: tomorrow)!, calendar: calendar))
        // Снимок без завтрашнего дня (старой версии) тоже не переворачивается.
        XCTAssertNil(WidgetSnapshot(day: today, items: [], streak: 0, overdue: 0, backlog: 0).rolled(to: tomorrow, calendar: calendar))
    }
}
