import PlannerCore
import SwiftUI
import WidgetKit

/// Виджет «Сегодня»: что сейчас и что дальше — со временем, галочками и серией.
/// Данные — снимок, который пишет приложение; галочка сразу меняет снимок (`ToggleTaskIntent`).
struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "QuickToday", provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("Сегодня")
        .description("Что сейчас и что дальше — с таймером, галочками и огоньком серии.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryRectangular, .accessoryCircular, .accessoryInline])
        // Поля задаём сами: 14 pt, на маленьких экранах 12 — системные съедают строку.
        .contentMarginsDisabled()
    }
}

struct TodayEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    /// Размер виджета — для полей.
    var size: CGSize = .zero
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: Date(), snapshot: .sample, size: context.displaySize)
    }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        // Пример — только для галереи виджетов; на экране без снимка честная заглушка «Открой Quick».
        completion(TodayEntry(date: Date(), snapshot: context.isPreview ? .sample : WidgetSnapshot.load(), size: context.displaySize))
    }

    /// Записи на моменты, когда виджет меняется сам (`WidgetSnapshot.timelineDates`): каждая минута часа
    /// вперёд — кольцо и «через 2 ч», начала и концы задач, конец «Вернуть», вечер, полночь. Секунды
    /// отсчётов тикают сами. Через три часа (частые записи кончились) WidgetKit читает снимок заново.
    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let now = Date()
        guard let snapshot = WidgetSnapshot.load() else {
            // Снимка ещё нет: приложение само перезагрузит виджет, когда его запишет.
            completion(Timeline(entries: [TodayEntry(date: now, snapshot: nil, size: context.displaySize)], policy: .never))
            return
        }
        let entries = snapshot.timelineDates(from: now).map {
            TodayEntry(date: $0, snapshot: snapshot, size: context.displaySize)
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(3 * 3600))))
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodayEntry

    private var isSystem: Bool { family == .systemSmall || family == .systemMedium || family == .systemLarge }

    var body: some View {
        let state = DayState(entry)
        content(state)
            .padding(isSystem ? (entry.size.height > 0 && entry.size.height < 160 ? 12 : 14) : 0)
            .containerBackground(for: .widget) {
                WidgetBackground(glow: isSystem ? state?.glow : nil)
            }
    }

    @ViewBuilder
    private func content(_ state: DayState?) -> some View {
        switch family {
        case .systemSmall: SmallTodayView(state: state)
        case .systemMedium: MediumTodayView(state: state)
        case .systemLarge: LargeTodayView(state: state)
        case .accessoryRectangular: RectangularTodayView(state: state)
        case .accessoryCircular: CircularTodayView(state: state)
        case .accessoryInline: InlineTodayView(state: state)
        default: MediumTodayView(state: state)
        }
    }
}

// MARK: - Экран блокировки

/// Прямоугольный: что сейчас, живое время и название главной задачи.
struct RectangularTodayView: View {
    let state: DayState?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let state, let item = state.focus {
                let hero = FocusHero(state: state, item: item)
                HStack(spacing: 4) {
                    Text(hero.label)
                        .lineLimit(1)
                    if let countdownTo = hero.countdownTo {
                        Countdown(from: state.date, to: countdownTo, font: .system(size: 12, weight: .semibold),
                                  color: .primary, width: 56, leading: true)
                    } else {
                        Text(hero.text)
                            .lineLimit(1)
                    }
                }
                .font(.system(size: 12, weight: .semibold))
                .widgetAccentable()
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(2)
            } else if let state, state.allDone {
                Label("Всё сделано", systemImage: "flame.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .widgetAccentable()
                Text(state.tomorrow.first.map { "Завтра " + WidgetText.short($0) } ?? "Серия " + WidgetText.days(state.snapshot.displayStreak))
                    .font(.system(size: 12))
                    .lineLimit(2)
            } else if let state {
                Text("Quick · сегодня")
                    .font(.system(size: 12, weight: .semibold))
                    .widgetAccentable()
                Text("Чистый день")
                    .font(.system(size: 14, weight: .semibold))
                if let next = state.tomorrow.first {
                    Text("Завтра " + WidgetText.short(next))
                        .font(.system(size: 12))
                        .lineLimit(1)
                }
            } else {
                Text("Quick")
                    .font(.system(size: 14, weight: .semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(DeepLink.today)
    }
}

/// Круглый: кольцо — сколько сделано за день, внутри — огонёк и серия.
struct CircularTodayView: View {
    let state: DayState?

    var body: some View {
        Gauge(value: state?.snapshot.progress ?? 0) {
            Image(systemName: "flame.fill")
        } currentValueLabel: {
            Text("\(state?.snapshot.displayStreak ?? 0)")
                .monospacedDigit()
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
        .accessibilityLabel("Серия " + WidgetText.days(state?.snapshot.displayStreak ?? 0))
        .widgetURL(DeepLink.today)
    }
}

/// Строка над часами: «13:00 Написать отчёт» или «Всё сделано».
struct InlineTodayView: View {
    let state: DayState?

    var body: some View {
        if let state, let item = state.focus {
            Label(WidgetText.short(item), systemImage: "bolt.fill")
        } else if let state, state.allDone {
            Label("Всё сделано · серия \(state.snapshot.displayStreak)", systemImage: "flame.fill")
        } else {
            Label("Quick", systemImage: "bolt.fill")
        }
    }
}

extension WidgetSnapshot {
    /// Пример для галереи виджетов и заглушки: одна задача идёт сейчас, дальше — ещё несколько.
    static var sample: WidgetSnapshot {
        let calendar = Calendar.current
        let now = Date()
        let day = calendar.startOfDay(for: now)
        let parts = calendar.dateComponents([.hour, .minute], from: now)
        let minutes = min(20 * 60, max(8 * 60, (parts.hour ?? 12) * 60 + (parts.minute ?? 0)))
        let current = minutes / 30 * 30 - 30
        let yesterday = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        return WidgetSnapshot(
            day: day,
            items: [
                Item(id: UUID(), title: "Созвон с командой", start: current - 90, duration: 30, isDone: true, colorHex: 0xFF6159),
                Item(id: UUID(), title: "Написать отчёт", start: current, duration: 90, isDone: false, colorHex: 0xFFC53D),
                Item(id: UUID(), title: "Купить запчасти", start: current + 120, duration: 45, isDone: false, colorHex: 0x5E9EFF),
                Item(id: UUID(), title: "Тренировка", start: current + 240, duration: 60, isDone: false, colorHex: 0x5CCB6E),
                Item(id: UUID(), title: "Почитать", start: nil, duration: 30, isDone: false, colorHex: 0x5CCB6E),
            ],
            streak: 4,
            overdue: 1,
            backlog: 7,
            overdueItems: [
                Item(id: UUID(), title: "Позвонить в банк", start: 11 * 60, duration: 15, isDone: false, colorHex: 0xFF6159, day: yesterday),
            ],
            tomorrowItems: [
                Item(id: UUID(), title: "Стендап", start: 9 * 60, duration: 15, isDone: false, colorHex: 0x5E9EFF),
            ],
            todayClosed: true,
            bestStreak: 9,
            week: [true, true, true, false, true, false, false]
        )
    }
}
