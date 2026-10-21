import Foundation

/// Снимок дня для виджета: приложение пишет его в контейнер группы, виджет только читает.
/// Виджет не видит базу SwiftData, поэтому здесь всё, что ему нужно, уже посчитано.
public struct WidgetSnapshot: Codable, Sendable, Equatable {
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
    public static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)?
            .appendingPathComponent(fileName)
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

    public var openCount: Int { items.filter { !$0.isDone }.count }
    public var doneCount: Int { items.filter { $0.isDone }.count }

    /// Ближайшая незавершённая задача с временем после `minutes` (минуты от полуночи).
    public func next(after minutes: Int) -> Item? {
        items.first { !$0.isDone && ($0.start ?? -1) + $0.duration > minutes }
    }
}
