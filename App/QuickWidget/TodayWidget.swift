import PlannerCore
import SwiftUI
import WidgetKit

/// Виджет «Сегодня»: ближайшая задача, серия, сколько сделано. Данные — снимок, который пишет приложение.
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuickToday", provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    LinearGradient(colors: [Color(hex: 0x121316), Color(hex: 0x1A1B1E)], startPoint: .top, endPoint: .bottom)
                }
        }
        .configurationDisplayName("Сегодня")
        .description("Ближайшая задача, серия дней и план на сегодня.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }
}

struct TodayEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: Date(), snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        // Пример — только для галереи виджетов; на экране без снимка честная заглушка «Открой Quick».
        completion(TodayEntry(date: Date(), snapshot: context.isPreview ? .sample : WidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let now = Date()
        let snapshot = WidgetSnapshot.load()
        var entries = [TodayEntry(date: now, snapshot: snapshot)]
        // Точки, в которые «ближайшая задача» меняется: концы задач с временем.
        if let snapshot, Calendar.current.isDate(snapshot.day, inSameDayAs: now) {
            let changes = snapshot.items
                .filter { !$0.isDone }
                .compactMap { item -> Date? in
                    guard let start = item.start else { return nil }
                    return Calendar.current.date(byAdding: .minute, value: start + item.duration, to: snapshot.day)
                }
                .filter { $0 > now }
                .sorted()
                .prefix(12)
            entries += changes.map { TodayEntry(date: $0, snapshot: snapshot) }
        }
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: now)) ?? now.addingTimeInterval(3600)
        completion(Timeline(entries: entries, policy: .after(tomorrow)))
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    private let accent = Color(hex: 0x3EE0A6)
    private let caption = Color(hex: 0xA1A1AA)
    private let muted = Color(hex: 0x8B8B94)
    private let flame = Color(hex: 0xFF9F43)

    private var minutesNow: Int {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: entry.date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// Снимок за сегодня; вчерашний не показываем как сегодняшний.
    private var snapshot: WidgetSnapshot? {
        guard let snapshot = entry.snapshot, Calendar.current.isDate(snapshot.day, inSameDayAs: entry.date) else { return nil }
        return snapshot
    }

    var body: some View {
        switch family {
        case .systemSmall: small
        case .accessoryRectangular: rectangular
        case .accessoryCircular: circular
        default: medium
        }
    }

    // MARK: - Маленький

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            Spacer(minLength: 0)
            if let snapshot {
                if let next = snapshot.next(after: minutesNow) {
                    Text(timeText(next))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accent)
                    Text(next.title)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(2)
                } else if snapshot.items.isEmpty {
                    Text("На сегодня пусто")
                        .font(.system(size: 14, weight: .semibold))
                } else {
                    Text("Всё сделано")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(accent)
                }
                Spacer(minLength: 0)
                Text(countsText(snapshot))
                    .font(.system(size: 11))
                    .foregroundStyle(caption)
            } else {
                Text("Открой Quick, чтобы обновить")
                    .font(.system(size: 13))
                    .foregroundStyle(caption)
            }
        }
        .foregroundStyle(.white)
        .widgetURL(URL(string: "quick://today"))
    }

    // MARK: - Средний

    private var medium: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                header
                Spacer(minLength: 0)
                if let snapshot {
                    Text("\(snapshot.doneCount) из \(snapshot.items.count)")
                        .font(.system(size: 22, weight: .bold))
                        .monospacedDigit()
                    Text("сделано")
                        .font(.system(size: 11))
                        .foregroundStyle(caption)
                    if snapshot.overdue > 0 {
                        Text("просрочено \(snapshot.overdue)")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(hex: 0xFF7A70))
                    }
                }
            }
            .frame(width: 92, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                if let snapshot {
                    let rows = upcomingRows(snapshot)
                    if rows.isEmpty {
                        Text(snapshot.items.isEmpty ? "На сегодня ничего не запланировано" : "Всё сделано — отличный день")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(snapshot.items.isEmpty ? caption : accent)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    } else {
                        ForEach(rows) { item in
                            row(item)
                        }
                        Spacer(minLength: 0)
                    }
                } else {
                    Text("Открой Quick, чтобы обновить виджет")
                        .font(.system(size: 13))
                        .foregroundStyle(caption)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
        }
        .foregroundStyle(.white)
        .widgetURL(URL(string: "quick://today"))
    }

    private func upcomingRows(_ snapshot: WidgetSnapshot) -> [WidgetSnapshot.Item] {
        let open = snapshot.items.filter { item in
            guard !item.isDone else { return false }
            guard let start = item.start else { return true }
            return start + item.duration > minutesNow
        }
        return Array(open.prefix(4))
    }

    private func row(_ item: WidgetSnapshot.Item) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color(hex: item.colorHex))
                .frame(width: 3, height: 22)
            Text(item.start.map { ClockGrid.format(minutes: $0) } ?? "день")
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(item.start.map { $0 <= minutesNow } == true ? accent : caption)
                .frame(width: 36, alignment: .leading)
            Text(item.title)
                .font(.system(size: 13))
                .lineLimit(1)
        }
    }

    // MARK: - Экран блокировки

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let snapshot, let next = snapshot.next(after: minutesNow) {
                Text(timeText(next))
                    .font(.system(size: 12, weight: .semibold))
                Text(next.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(2)
            } else if let snapshot {
                Text("Quick · сегодня")
                    .font(.system(size: 12, weight: .semibold))
                Text(snapshot.items.isEmpty ? "Пусто" : "Всё сделано")
                    .font(.system(size: 14, weight: .semibold))
            } else {
                Text("Quick")
                    .font(.system(size: 14, weight: .semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(URL(string: "quick://today"))
    }

    private var circular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 14, weight: .bold))
                Text("\(snapshot?.streak ?? 0)")
                    .font(.system(size: 16, weight: .bold))
                    .monospacedDigit()
            }
        }
        .widgetURL(URL(string: "quick://today"))
    }

    // MARK: - Общее

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(accent)
            Text(dayTitle)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(caption)
                .lineLimit(1)
            Spacer(minLength: 0)
            if let streak = snapshot?.streak, streak > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "flame.fill")
                    Text("\(streak)")
                        .monospacedDigit()
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(flame)
            }
        }
    }

    private var dayTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.dateFormat = "EEE, d MMM"
        let text = formatter.string(from: entry.date)
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    private func timeText(_ item: WidgetSnapshot.Item) -> String {
        guard let start = item.start else { return "Весь день" }
        if start <= minutesNow { return "Сейчас · до " + ClockGrid.format(minutes: start + item.duration) }
        return ClockGrid.format(minutes: start) + "–" + ClockGrid.format(minutes: start + item.duration)
    }

    private func countsText(_ snapshot: WidgetSnapshot) -> String {
        let open = snapshot.openCount
        if open == 0 { return snapshot.items.isEmpty ? "задач нет" : "сделано \(snapshot.doneCount)" }
        return "ещё \(open) · сделано \(snapshot.doneCount)"
    }
}

extension WidgetSnapshot {
    /// Пример для галереи виджетов и заглушки.
    static let sample = WidgetSnapshot(
        day: Calendar.current.startOfDay(for: Date()),
        items: [
            Item(id: UUID(), title: "Созвон с командой", start: 10 * 60, duration: 30, isDone: true, colorHex: 0xFF6159),
            Item(id: UUID(), title: "Написать отчёт", start: 11 * 60 + 30, duration: 60, isDone: false, colorHex: 0xFFC53D),
            Item(id: UUID(), title: "Купить запчасти", start: 15 * 60, duration: 45, isDone: false, colorHex: 0x5E9EFF),
            Item(id: UUID(), title: "Почитать", start: nil, duration: 30, isDone: false, colorHex: 0x5CCB6E),
        ],
        streak: 4,
        overdue: 1,
        backlog: 7
    )
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
