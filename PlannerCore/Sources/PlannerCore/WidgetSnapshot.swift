import Foundation

/// Снимок дня для виджета: приложение пишет его в контейнер группы, виджет только читает.
/// Виджет не видит базу SwiftData, поэтому здесь всё, что ему нужно, уже посчитано.
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

        public init(id: UUID, title: String, start: Int?, duration: Int, isDone: Bool, colorHex: UInt32) {
            self.id = id
            self.title = title
            self.start = start
            self.duration = duration
            self.isDone = isDone
            self.colorHex = colorHex
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

    public init(day: Date, items: [Item], streak: Int, overdue: Int, backlog: Int, generatedAt: Date = Date()) {
        self.day = day
        self.items = items
        self.streak = streak
        self.overdue = overdue
        self.backlog = backlog
        self.generatedAt = generatedAt
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
            && overdue == other.overdue && backlog == other.backlog
    }

    public var openCount: Int { items.filter { !$0.isDone }.count }
    public var doneCount: Int { items.filter { $0.isDone }.count }

    /// Ближайшая незавершённая задача: с временем — та, что ещё не закончилась к `minutes`
    /// (минуты от полуночи), без времени — любая открытая.
    public func next(after minutes: Int) -> Item? {
        items.first { item in
            guard !item.isDone else { return false }
            guard let start = item.start else { return true }
            return start + item.duration > minutes
        }
    }
}
