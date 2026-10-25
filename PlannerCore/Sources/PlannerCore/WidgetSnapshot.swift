import Foundation

/// Снимок дня для виджета: приложение пишет его в контейнер группы, виджет только читает
/// (и сам отмечает в нём галочки, поставленные в виджете). Виджет не видит базу SwiftData,
/// поэтому здесь всё, что ему нужно, уже посчитано.
public struct WidgetSnapshot: Codable, Sendable {
    public struct Item: Codable, Sendable, Equatable, Identifiable {
        public var id: UUID
        public var title: String
        /// Минуты от 0:00; `nil` — весь день.
        public var start: Int?
        public var duration: Int
        public var isDone: Bool
        /// Цвет точки (квадрант или проект) как 0xRRGGBB.
        public var colorHex: UInt32
        /// День задачи — у просроченных (у сегодняшних и завтрашних не нужен).
        public var day: Date?
        /// Копия рутины: несделанная не становится просроченной.
        public var isRoutine: Bool?

        public init(id: UUID, title: String, start: Int?, duration: Int, isDone: Bool, colorHex: UInt32,
                    day: Date? = nil, isRoutine: Bool? = nil) {
            self.id = id
            self.title = title
            self.start = start
            self.duration = duration
            self.isDone = isDone
            self.colorHex = colorHex
            self.day = day
            self.isRoutine = isRoutine
        }
    }

    /// Начало дня, за который снимок.
    public var day: Date
    /// Задачи дня: сначала с временем по порядку, потом без времени.
    public var items: [Item]
    public var streak: Int
    public var overdue: Int
    public var backlog: Int
    public var generatedAt: Date
    // Дальше — необязательные поля: снимок старой версии приложения тоже читается.
    /// Просроченные, старые первыми (не больше дюжины).
    public var overdueItems: [Item]?
    /// Задачи завтра — что впереди, когда сегодня всё сделано, и план на утро, если приложение не открывали.
    public var tomorrowItems: [Item]?
    /// Сегодня уже что-то сделано, и серия его учитывает.
    public var todayClosed: Bool?
    /// Лучшая серия за всё время.
    public var bestStreak: Int?
    /// Понедельник…воскресенье недели снимка: был ли день «закрыт».
    public var week: [Bool]?
    /// Последняя галочка, поставленная в виджете, — чтобы минуту-другую предлагать «Вернуть».
    public var lastDone: WidgetAction?

    public init(day: Date, items: [Item], streak: Int, overdue: Int, backlog: Int, generatedAt: Date = Date(),
                overdueItems: [Item]? = nil, tomorrowItems: [Item]? = nil, todayClosed: Bool? = nil,
                bestStreak: Int? = nil, week: [Bool]? = nil, lastDone: WidgetAction? = nil) {
        self.day = day
        self.items = items
        self.streak = streak
        self.overdue = overdue
        self.backlog = backlog
        self.generatedAt = generatedAt
        self.overdueItems = overdueItems
        self.tomorrowItems = tomorrowItems
        self.todayClosed = todayClosed
        self.bestStreak = bestStreak
        self.week = week
        self.lastDone = lastDone
    }

    public static let appGroup = "group.com.ninogvatania.planner"
    public static let fileName = "widget-snapshot.json"

    /// Файл в контейнере группы приложений; `nil`, если группа недоступна (нет права App Groups).
    /// На Linux (тесты пакета) контейнеров нет.
    public static var fileURL: URL? {
        #if canImport(Darwin)
        return FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(fileName)
        #else
        return nil
        #endif
    }

    public func save() throws {
        guard let url = Self.fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    public static func load() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    /// Содержимое совпадает (время создания не в счёт) — перезаписывать файл не нужно.
    public func hasSameContent(as other: WidgetSnapshot?) -> Bool {
        guard let other else { return false }
        return day == other.day && items == other.items && streak == other.streak
            && overdue == other.overdue && backlog == other.backlog && overdueItems == other.overdueItems
            && tomorrowItems == other.tomorrowItems && todayClosed == other.todayClosed
            && bestStreak == other.bestStreak && week == other.week && lastDone == other.lastDone
    }

    public var openCount: Int { items.filter { !$0.isDone }.count }

    public var doneCount: Int { items.filter { $0.isDone }.count }

    /// Просроченные, ещё не закрытые галочкой в виджете.
    public var openOverdue: [Item] { (overdueItems ?? []).filter { !$0.isDone } }

    /// Сделано сегодня: задачи дня и просроченные, закрытые в виджете.
    public var doneTodayCount: Int { doneCount + (overdueItems ?? []).filter(\.isDone).count }

    /// Доля сделанного за день, 0…1.
    public var progress: Double { items.isEmpty ? 0 : Double(doneCount) / Double(items.count) }

    /// Сегодня уже что-то сделано — в приложении или галочкой в виджете.
    public var isTodayClosed: Bool { todayClosed == true || doneTodayCount > 0 }

    /// Серия с галочками, поставленными в виджете: первая сделанная сегодня задача продлевает её на день.
    public var displayStreak: Int { todayClosed == false && doneTodayCount > 0 ? streak + 1 : streak }

    /// С какого часа несделанный день подсвечивается: серия вот-вот погаснет.
    public static let atRiskHour = 18

    /// Вечер, сегодня ничего не сделано, а серия есть — погаснет в полночь.
    public func streakAtRisk(at minutes: Int) -> Bool {
        !isTodayClosed && streak > 0 && minutes >= Self.atRiskHour * 60
    }

    /// Сколько секунд после галочки в виджете предлагать «Вернуть».
    public static let undoWindow: TimeInterval = 120

    /// Задача, отмеченная в виджете только что (и всё ещё сделанная), — для «Вернуть».
    public func justDone(at date: Date) -> Item? {
        guard let lastDone, lastDone.kind == .setDone, lastDone.done, let id = lastDone.id,
              date.timeIntervalSince(lastDone.at) < Self.undoWindow
        else { return nil }
        return (items + (overdueItems ?? [])).first { $0.id == id && $0.isDone }
    }

    /// Неделя с сегодняшним днём, закрытым галочкой в виджете. Понедельник — первый.
    public func displayWeek(calendar: Calendar = .current) -> [Bool]? {
        guard var week, week.count == 7 else { return nil }
        if isTodayClosed { week[Self.weekIndex(of: day, calendar: calendar)] = true }
        return week
    }

    /// Номер дня в неделе с понедельника: 0 — понедельник, 6 — воскресенье.
    public static func weekIndex(of date: Date, calendar: Calendar = .current) -> Int {
        (calendar.component(.weekday, from: date) + 5) % 7
    }

    /// Как задача стоит относительно `minutes` (минуты от полуночи дня снимка).
    public func timing(of item: Item, at minutes: Int) -> WidgetTiming {
        if item.isDone { return .done }
        if let itemDay = item.day, itemDay < day { return .overdue(itemDay) }
        guard let start = item.start else { return .allDay }
        if minutes < start { return .later(minutes: start - minutes) }
        let end = start + item.duration
        if minutes < end { return .now(minutesLeft: end - minutes) }
        return .missed(minutesAgo: minutes - end)
    }

    /// Задача только что кончилась (не позже `justEndedWindow` минут назад), а не отмечена:
    /// спросить «Готово?», пока ничего другого не идёт.
    public static let justEndedWindow = 30

    /// Что делать дальше, по порядку: идущая сейчас; только что кончившаяся, если ничего не идёт;
    /// предстоящие с временем; без времени; давно пропущенные сегодня. Сделанных нет.
    public func agenda(at minutes: Int) -> [Item] {
        let open = items.filter { !$0.isDone }
        let running = open.contains { item in
            if case .now = timing(of: item, at: minutes) { return true }
            return false
        }
        func rank(_ item: Item) -> Int {
            switch timing(of: item, at: minutes) {
            case .now: return 0
            case .missed(let ago) where !running && ago <= Self.justEndedWindow: return 1
            case .later: return 2
            case .allDay: return 3
            default: return 4
            }
        }
        // Задачи уже по времени — устойчивая сортировка по группе его сохраняет. Среди пропущенных
        // первой идёт та, что кончилась позже.
        return open.enumerated()
            .sorted { a, b in
                let (ra, rb) = (rank(a.element), rank(b.element))
                if ra != rb { return ra < rb }
                return ra == 4 ? a.offset > b.offset : a.offset < b.offset
            }
            .map(\.element)
    }

    /// Ближайшая задача с временем после `minutes` — до неё свободно.
    public func nextTimed(after minutes: Int) -> Item? {
        items.first { item in
            guard !item.isDone, let start = item.start else { return false }
            return start > minutes
        }
    }

    /// Отрезок полоски дня в минутах: по целым часам, не уже 8:00–22:00, вмещает задачи с временем
    /// и текущую минуту `minutes`.
    public func timelineBounds(at minutes: Int) -> ClosedRange<Int> {
        let starts = items.compactMap { $0.start }
        let ends = items.compactMap { item in item.start.map { $0 + item.duration } }
        let earliest = min(minutes, starts.min() ?? minutes)
        let latest = max(minutes, ends.max() ?? minutes)
        let lower = max(0, min(8 * 60, earliest / 60 * 60))
        let upper = min(24 * 60, max(22 * 60, (latest + 59) / 60 * 60))
        return lower...upper
    }

    public func isDone(_ id: UUID) -> Bool {
        (items + (overdueItems ?? [])).first { $0.id == id }?.isDone ?? false
    }

    /// Снимок после галочки в виджете в момент `date`: задача дня или просроченная меняет состояние.
    /// Закрытая просроченная остаётся в списке скрытой — её можно вернуть, и она идёт в серию.
    public func toggling(_ id: UUID, at date: Date = Date()) -> WidgetSnapshot {
        var copy = self
        let done: Bool
        if let index = copy.items.firstIndex(where: { $0.id == id }) {
            copy.items[index].isDone.toggle()
            done = copy.items[index].isDone
        } else if let index = copy.overdueItems?.firstIndex(where: { $0.id == id }), var item = copy.overdueItems?[index] {
            item.isDone.toggle()
            done = item.isDone
            copy.overdueItems?[index] = item
            copy.overdue = max(0, copy.overdue + (done ? -1 : 1))
        } else {
            return self
        }
        copy.lastDone = done ? .setDone(id, true, at: date) : nil
        return copy
    }

    /// Снимок после «На сегодня» в виджете: открытые просроченные — сегодняшние на весь день.
    public func movingOverdueToToday() -> WidgetSnapshot {
        var copy = self
        let moved = openOverdue.map { item -> Item in
            var copy = item
            copy.day = nil
            copy.start = nil
            return copy
        }
        copy.items += moved
        copy.overdueItems = (overdueItems ?? []).filter(\.isDone)
        copy.overdue = max(0, overdue - moved.count)
        return copy
    }

    /// Когда перерисовать виджет, начиная с `now`: каждую минуту час вперёд и раз в 5 минут до трёх
    /// часов (если сегодня есть задачи с временем; иначе раз в 15 минут), моменты задач (за 3 ч, за час,
    /// за 10 минут, начало, за час до конца, конец, полчаса после), конец «Вернуть», вечерний час серии
    /// и полночь. По порядку, не больше 200.
    public func timelineDates(from now: Date, calendar: Calendar = .current) -> [Date] {
        let today = calendar.startOfDay(for: now)
        let base = calendar.dateInterval(of: .minute, for: now)?.start ?? now
        let snapshot = rolled(to: now, calendar: calendar) ?? self
        var dates: Set<Date> = [now]
        func add(minutes: Int, from origin: Date) {
            if let date = calendar.date(byAdding: .minute, value: minutes, to: origin), date > now { dates.insert(date) }
        }
        if snapshot.items.contains(where: { !$0.isDone && $0.start != nil }) {
            for minutes in 1...60 { add(minutes: minutes, from: base) }
            for minutes in stride(from: 65, through: 180, by: 5) { add(minutes: minutes, from: base) }
        } else {
            for minutes in stride(from: 15, through: 180, by: 15) { add(minutes: minutes, from: base) }
        }
        for item in snapshot.items where !item.isDone {
            guard let start = item.start else { continue }
            let end = start + item.duration
            for minutes in [start - 180, start - 60, start - 10, start, end - 60, end, end + 30] {
                add(minutes: minutes, from: today)
            }
        }
        if let lastDone = snapshot.lastDone {
            let end = lastDone.at.addingTimeInterval(Self.undoWindow)
            if end > now { dates.insert(end) }
        }
        add(minutes: Self.atRiskHour * 60, from: today)
        if let midnight = calendar.date(byAdding: .day, value: 1, to: today) {
            dates.insert(midnight.addingTimeInterval(1))
        }
        return Array(dates.sorted().prefix(200))
    }

    /// Снимок, увиденный в день `day`. Свой день — как есть. Наступило завтра, а приложение ещё не
    /// открывали — завтрашние задачи становятся сегодняшними, несделанные вчерашние — просроченными,
    /// серия живёт, только если вчера что-то сделано. Старше — `nil`: показывать нечего.
    public func rolled(to day: Date, calendar: Calendar = .current) -> WidgetSnapshot? {
        let today = calendar.startOfDay(for: day)
        let own = calendar.startOfDay(for: self.day)
        if own == today { return self }
        guard let next = calendar.date(byAdding: .day, value: 1, to: own), next == today else { return nil }
        let leftOver = items.filter { !$0.isDone && $0.isRoutine != true }.map { item -> Item in
            var copy = item
            copy.day = own
            return copy
        }
        // Новая неделя начинается с чистых точек.
        let newWeek = Self.weekIndex(of: today, calendar: calendar) == 0
        return WidgetSnapshot(
            day: today,
            items: tomorrowItems ?? [],
            streak: isTodayClosed ? displayStreak : 0,
            overdue: overdue + leftOver.count,
            backlog: backlog,
            generatedAt: generatedAt,
            overdueItems: Array((openOverdue + leftOver).prefix(12)),
            tomorrowItems: nil,
            todayClosed: false,
            bestStreak: bestStreak.map { max($0, displayStreak) },
            week: newWeek ? week.map { _ in Array(repeating: false, count: 7) } : displayWeek(calendar: calendar),
            lastDone: nil
        )
    }
}

/// Положение задачи относительно текущей минуты.
public enum WidgetTiming: Equatable, Sendable {
    /// Идёт, до конца `minutesLeft` минут.
    case now(minutesLeft: Int)
    /// Начнётся через `minutes` минут.
    case later(minutes: Int)
    case allDay
    /// Сегодня, кончилась `minutesAgo` минут назад, не отмечена.
    case missed(minutesAgo: Int)
    /// Не сделана в прошлый день.
    case overdue(Date)
    case done
}

/// Действие в виджете: приложение применит его при следующем запуске или возврате.
public struct WidgetAction: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        /// Галочка: задача `id` сделана (`done`) или снова открыта.
        case setDone
        /// «На сегодня»: все просроченные — на день действия, на весь день.
        case overdueToToday
    }

    public var kind: Kind
    public var id: UUID?
    public var done: Bool
    public var at: Date

    public init(kind: Kind, id: UUID?, done: Bool, at: Date) {
        self.kind = kind
        self.id = id
        self.done = done
        self.at = at
    }

    public static func setDone(_ id: UUID, _ done: Bool, at: Date) -> WidgetAction {
        WidgetAction(kind: .setDone, id: id, done: done, at: at)
    }

    public static func overdueToToday(at: Date) -> WidgetAction {
        WidgetAction(kind: .overdueToToday, id: nil, done: false, at: at)
    }
}

/// Очередь действий из виджета — файл в контейнере группы приложений.
public enum WidgetActions {
    public static let fileName = "widget-actions.json"

    static var fileURL: URL? {
        #if canImport(Darwin)
        return FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: WidgetSnapshot.appGroup)?
            .appendingPathComponent(fileName)
        #else
        return nil
        #endif
    }

    /// Действия по порядку, в каком их сделали.
    public static func load() -> [WidgetAction] {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return ordered((try? decoder.decode([WidgetAction].self, from: data)) ?? [])
    }

    public static func append(_ action: WidgetAction) throws {
        try write(load() + [action])
    }

    /// Убрать применённые: те, что не позже `date` (новые, пришедшие пока приложение применяло, остаются).
    public static func remove(upTo date: Date) {
        let rest = load().filter { $0.at > date }
        try? write(rest)
    }

    /// По времени; одновременные — в порядке записи. Применять подряд: поставил и снял — задача открыта.
    public static func ordered(_ actions: [WidgetAction]) -> [WidgetAction] {
        actions.enumerated()
            .sorted { ($0.element.at, $0.offset) < ($1.element.at, $1.offset) }
            .map(\.element)
    }

    private static func write(_ actions: [WidgetAction]) throws {
        guard let url = fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(actions).write(to: url, options: .atomic)
    }
}
