import XCTest
@testable import PlannerCore

final class QuickAddParserTests: XCTestCase {
    private var parser: QuickAddParser!

    override func setUp() {
        super.setUp()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        // Вторник, 20 октября 2026.
        let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 12))!
        parser = QuickAddParser(calendar: calendar, today: today)
    }

    private func check(
        _ text: String,
        title: String,
        day: Int?,
        start: Int?,
        duration: Int = 30,
        quadrant: Quadrant? = nil,
        project: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let task = parser.parseTask(text)
        XCTAssertEqual(task.title, title, "название: \(text)", file: file, line: line)
        XCTAssertEqual(task.dayOffset, day, "день: \(text)", file: file, line: line)
        XCTAssertEqual(task.start, start, "время: \(text)", file: file, line: line)
        XCTAssertEqual(task.duration, duration, "длительность: \(text)", file: file, line: line)
        XCTAssertEqual(task.quadrant, quadrant, "квадрант: \(text)", file: file, line: line)
        XCTAssertEqual(task.project, project, "проект: \(text)", file: file, line: line)
    }

    private func t(_ h: Int, _ m: Int = 0) -> Int { h * 60 + m }

    func testDatesAndTimes() {
        check("в пятницу в 15 созвон на час, важно срочно", title: "Созвон", day: 3, start: t(15), duration: 60, quadrant: .urgentImportant)
        check("в час дня позвонить маме", title: "Позвонить маме", day: 0, start: t(13))
        check("купить молоко", title: "Купить молоко", day: nil, start: nil)
        check("сегодня вечером тренировка на полтора часа", title: "Тренировка", day: 0, start: t(19), duration: 90)
        check("послезавтра в 11 к врачу", title: "К врачу", day: 2, start: t(11))
        check("в 5 забрать детей", title: "Забрать детей", day: 0, start: t(17))
        check("завтра утром пробежка 20 минут", title: "Пробежка", day: 1, start: t(9), duration: 20)
        check("в понедельник в 9:30 стендап на 15 минут #работа", title: "Стендап", day: 6, start: t(9, 30), duration: 15, project: "Работа")
        check("в 19:00 ужин с Машей на 2 часа", title: "Ужин с Машей", day: 0, start: t(19), duration: 120)
        check("в 10 утра позвонить в банк", title: "Позвонить в банк", day: 0, start: t(10))
        check("в 12 ночи выезд", title: "Выезд", day: 0, start: 0)
        check("днем в 2 обед с Петей", title: "Обед с Петей", day: 0, start: t(14))
    }

    func testPartOfDayWithNumber() {
        check("Вечером в 7 кино", title: "Кино", day: 0, start: t(19))
        check("Утром в 6 пробежка", title: "Пробежка", day: 0, start: t(6))
        check("Посмотреть фильм вечером в 21:30", title: "Посмотреть фильм", day: 0, start: t(21, 30))
        check("Пробежка в 6 утра", title: "Пробежка", day: 0, start: t(6))
    }

    func testPunctuationDoesNotBreakParsing() {
        check("Созвон в 9:30.", title: "Созвон", day: 0, start: t(9, 30))
        check("Позвонить маме в 18:00!", title: "Позвонить маме", day: 0, start: t(18))
        check("Купить хлеб на 15 мин.", title: "Купить хлеб", day: nil, start: nil, duration: 15)
    }

    func testQuadrantWords() {
        check("Созвон в 10 вечера на 30 минут важно и срочно", title: "Созвон", day: 0, start: t(22), quadrant: .urgentImportant)
        check("Сделать отчёт, не срочно но важно", title: "Сделать отчёт", day: nil, start: nil, quadrant: .important)
        check("срочняк: оплатить штраф", title: "Оплатить штраф", day: nil, start: nil, quadrant: .urgent)
        check("неважно: разобрать стол", title: "Разобрать стол", day: nil, start: nil, quadrant: .other)
        check("завтра не срочно но важно: дочитать книгу", title: "Дочитать книгу", day: 1, start: nil, quadrant: .important)
        check("в пятницу в 15 созвон на час, важное срочное", title: "Созвон", day: 3, start: t(15), duration: 60, quadrant: .urgentImportant)
        check("!1 позвонить", title: "Позвонить", day: nil, start: nil, quadrant: .urgentImportant)
    }

    func testTitleCleanup() {
        check("Ещё раз проверить", title: "Ещё раз проверить", day: nil, start: nil)
        check("Срочно! позвонить в банк завтра.", title: "Позвонить в банк", day: 1, start: nil, quadrant: .urgent)
        check("важно: сдать отчёт в пятницу в 15", title: "Сдать отчёт", day: 3, start: t(15), quadrant: .important)
        XCTAssertEqual(parser.parseTask("").title, "Новая задача")
    }

    func testCommands() {
        XCTAssertEqual(parser.parse("Что у меня завтра?"), .agenda(dayOffset: 1))
        XCTAssertEqual(parser.parse("что сегодня"), .agenda(dayOffset: 0))
        XCTAssertEqual(parser.parse("перенеси просроченные на завтра"), .fitOverdue(dayOffset: 1))
        XCTAssertEqual(parser.parse("Перенеси просроченные на сегодня"), .fitOverdue(dayOffset: 0))
        if case .task(let task) = parser.parse("завтра в 10 созвон") {
            XCTAssertEqual(task.start, t(10))
        } else {
            XCTFail("ожидалась задача")
        }
    }
}
