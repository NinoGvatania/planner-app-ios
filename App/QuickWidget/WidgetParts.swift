import AppIntents
import PlannerCore
import SwiftUI
import WidgetKit

/// Цвета виджета — те же токены, что в приложении (docs/PLAN.md).
enum WidgetPalette {
    static let text = Color(hex: 0xF3F4F6)
    static let caption = Color(hex: 0xA1A1AA)
    static let muted = Color(hex: 0x8B8B94)
    static let accent = Color(hex: 0x3EE0A6)
    static let onAccent = Color(hex: 0x05261A)
    static let flame = Color(hex: 0xFF9F43)
    static let overdue = Color(hex: 0xFF7A70)
    /// «Готово?» у только что кончившейся задачи.
    static let ask = Color(hex: 0xFFC53D)
    static let card = Color.white.opacity(0.06)
    static let line = Color.white.opacity(0.08)
    static let track = Color.white.opacity(0.10)
    static let flameGradient = LinearGradient(colors: [Color(hex: 0xFFD166), Color(hex: 0xFF9F43), Color(hex: 0xFF5E3A)],
                                              startPoint: .top, endPoint: .bottom)

    /// Цвет задачи; серый «без квадранта» — светлее, чтобы кольцо было видно.
    static func task(_ item: WidgetSnapshot.Item) -> Color {
        item.colorHex == 0x8C8C96 ? caption : Color(hex: item.colorHex)
    }
}

/// Ссылки в приложение (разбирает `PlannerScreen.openLink`).
enum DeepLink {
    static let today = URL(string: "quick://today")!
    static let add = URL(string: "quick://add")!
    static let voice = URL(string: "quick://voice")!
    static let overdue = URL(string: "quick://overdue")!
    static let streak = URL(string: "quick://streak")!
    static let backlog = URL(string: "quick://backlog")!
    static func task(_ id: UUID) -> URL { URL(string: "quick://task/\(id.uuidString)") ?? today }
}

/// Снимок глазами записи таймлайна: на её день (после полуночи — уже завтрашний) и её минуту.
struct DayState {
    let snapshot: WidgetSnapshot
    let date: Date
    let minutes: Int
    let agenda: [WidgetSnapshot.Item]

    init?(_ entry: TodayEntry) {
        guard let snapshot = entry.snapshot?.rolled(to: entry.date) else { return nil }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: entry.date)
        self.snapshot = snapshot
        date = entry.date
        minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        agenda = snapshot.agenda(at: minutes)
    }

    /// Открытые просроченные.
    var overdue: [WidgetSnapshot.Item] { snapshot.openOverdue }
    var tomorrow: [WidgetSnapshot.Item] { snapshot.tomorrowItems ?? [] }
    /// Сделанные сегодня; только что отмеченная в виджете — первой.
    var done: [WidgetSnapshot.Item] {
        let items = snapshot.items.filter(\.isDone)
        guard let just = justDone, let index = items.firstIndex(where: { $0.id == just.id }) else { return items }
        return [items[index]] + items.enumerated().filter { $0.offset != index }.map(\.element)
    }
    /// Сегодня всё сделано (и было что делать).
    var allDone: Bool { !snapshot.items.isEmpty && agenda.isEmpty }
    /// Серия горит: сегодня уже что-то сделано.
    var flameLit: Bool { snapshot.isTodayClosed }
    /// Вечер без единой галочки — серия погаснет в полночь.
    var atRisk: Bool { snapshot.streakAtRisk(at: minutes) }
    /// Только что отмечена в виджете — можно вернуть.
    var justDone: WidgetSnapshot.Item? { snapshot.justDone(at: date) }

    /// Главная задача: что делать сейчас или следующей (в свободное время — задача без времени);
    /// на пустой сегодня — самая старая просроченная.
    var focus: WidgetSnapshot.Item? { snapshot.focus(at: minutes) ?? (snapshot.items.isEmpty ? overdue.first : nil) }

    func timing(_ item: WidgetSnapshot.Item) -> WidgetTiming { snapshot.timing(of: item, at: minutes) }

    /// Строки списка: что дальше, потом просроченные, потом сделанные сегодня (их можно вернуть).
    func rows(limit: Int, skipping skipped: UUID? = nil) -> [WidgetSnapshot.Item] {
        let list = (agenda + overdue + done).filter { $0.id != skipped }
        return Array(list.prefix(max(0, limit)))
    }

    /// Сколько несделанных (сегодня и просроченных) не влезло в список из `shown` строк.
    func hiddenOpen(shown: [WidgetSnapshot.Item], skipping skipped: UUID? = nil) -> Int {
        let shownIDs = Set(shown.map(\.id))
        return (agenda + overdue).filter { $0.id != skipped && !shownIDs.contains($0.id) }.count
    }

    /// Момент сегодня по минутам от полуночи.
    func moment(_ minutes: Int) -> Date {
        let calendar = Calendar.current
        return calendar.date(byAdding: .minute, value: minutes, to: calendar.startOfDay(for: date)) ?? date
    }

    var midnight: Date { moment(24 * 60) }

    /// Начало и конец задачи сегодня — для живой полоски «сколько прошло».
    func interval(_ item: WidgetSnapshot.Item) -> ClosedRange<Date>? {
        guard let start = item.start else { return nil }
        return moment(start)...moment(start + max(1, item.duration))
    }

    /// Какая доля задачи ещё впереди (кольцо вокруг галочки «тает»).
    func remaining(_ item: WidgetSnapshot.Item) -> Double? {
        guard case .now(let left) = timing(item) else { return nil }
        return Double(left) / Double(max(1, item.duration))
    }

    /// Подсветка фона: идёт задача — её цветом, свободное время или всё сделано — мятным,
    /// вечер с серией под угрозой — тёплым.
    var glow: Color? {
        if atRisk { return WidgetPalette.flame }
        if allDone { return WidgetPalette.accent }
        guard let focus else { return nil }
        switch timing(focus) {
        case .now: return WidgetPalette.task(focus)
        case .allDay: return snapshot.nextTimed(after: minutes) == nil ? nil : WidgetPalette.accent
        default: return nil
        }
    }
}

/// Подписи: время задачи, сколько осталось, дни.
enum WidgetText {
    private static let weekdays = ["вс", "пн", "вт", "ср", "чт", "пт", "сб"]
    private static let months = ["янв", "фев", "мар", "апр", "мая", "июн", "июл", "авг", "сен", "окт", "ноя", "дек"]

    /// «13:00–14:00», без времени — «Весь день».
    static func range(_ item: WidgetSnapshot.Item) -> String {
        guard let start = item.start else { return "Весь день" }
        return ClockGrid.format(minutes: start) + "–" + ClockGrid.format(minutes: start + item.duration)
    }

    /// «25 мин», «1 ч 5 мин».
    static func duration(_ minutes: Int) -> String { ClockGrid.formatDuration(max(1, minutes)) }

    /// Через сколько, коротко и с точностью до получаса: «2 ч», «2,5 ч».
    static func roughHours(_ minutes: Int) -> String {
        let halves = (minutes + 15) / 30
        return halves % 2 == 0 ? "\(halves / 2) ч" : "\(halves / 2),5 ч"
    }

    /// «Сб, 25 окт» или без месяца — «Сб, 25».
    static func dayTitle(_ date: Date, withMonth: Bool = true) -> String {
        let parts = Calendar.current.dateComponents([.weekday, .day, .month], from: date)
        let weekday = weekdays[((parts.weekday ?? 1) - 1 + 7) % 7]
        let month = months[((parts.month ?? 1) - 1 + 12) % 12]
        let title = capitalized(weekday) + ", \(parts.day ?? 1)"
        return withMonth ? title + " " + month : title
    }

    /// День просроченной задачи относительно сегодня: «вчера», «пт» (на этой неделе), «21 окт».
    static func overdueDay(_ day: Date, today: Date) -> String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: day), to: calendar.startOfDay(for: today)).day ?? 0
        if days == 1 { return "вчера" }
        let parts = calendar.dateComponents([.weekday, .day, .month], from: day)
        if days < 7 { return weekdays[((parts.weekday ?? 1) - 1 + 7) % 7] }
        return "\(parts.day ?? 1) " + months[((parts.month ?? 1) - 1 + 12) % 12]
    }

    static func capitalized(_ text: String) -> String { text.prefix(1).uppercased() + String(text.dropFirst()) }

    /// «9:00 Стендап».
    static func short(_ item: WidgetSnapshot.Item) -> String {
        (item.start.map { ClockGrid.format(minutes: $0) + " " } ?? "") + item.title
    }

    /// «задача», «задачи», «задач».
    static func plural(_ n: Int, _ one: String, _ few: String, _ many: String) -> String {
        let mod10 = n % 10, mod100 = n % 100
        if mod10 == 1 && mod100 != 11 { return one }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return few }
        return many
    }

    static func days(_ n: Int) -> String { "\(n) " + plural(n, "день", "дня", "дней") }

    /// Что сказать справа в строке списка и каким цветом. `nil` — живой отсчёт (рисует строка) или ничего.
    static func trailing(_ item: WidgetSnapshot.Item, timing: WidgetTiming, state: DayState) -> (text: String, color: Color)? {
        switch timing {
        case .now: return nil
        case .later(let minutes):
            if minutes <= 60 { return nil }
            return (item.start.map { ClockGrid.format(minutes: $0) } ?? "", WidgetPalette.caption)
        case .allDay: return nil
        case .missed(let ago):
            if ago <= WidgetSnapshot.justEndedWindow { return ("готово?", WidgetPalette.ask) }
            return (item.start.map { ClockGrid.format(minutes: $0) } ?? "", WidgetPalette.overdue)
        case .overdue(let day): return (overdueDay(day, today: state.snapshot.day), WidgetPalette.overdue)
        case .done:
            if state.justDone?.id == item.id { return ("готово", WidgetPalette.accent) }
            guard let start = item.start else { return nil }
            return (ClockGrid.format(minutes: start), WidgetPalette.muted)
        }
    }
}

/// Живой обратный отсчёт до `to`: тикает сам, без перерисовки таймлайна.
struct Countdown: View {
    let from: Date
    let to: Date
    var font: Font = .system(size: 13, weight: .semibold)
    var color: Color = WidgetPalette.accent
    var width: CGFloat = 52
    var leading = false
    /// Насколько можно ужать крупный отсчёт на узком экране (мелкий — не ужимается: он и так 11–13 pt).
    var minScale: CGFloat = 1

    var body: some View {
        // Таймер занимает всю данную ширину — рамка держит его на месте (на узком экране — уже).
        Text(timerInterval: min(from, to)...to, countsDown: true)
            .font(font)
            .monospacedDigit()
            .foregroundStyle(color)
            .multilineTextAlignment(leading ? .leading : .trailing)
            .lineLimit(1)
            .minimumScaleFactor(minScale)
            .frame(maxWidth: width, alignment: leading ? .leading : .trailing)
    }
}

/// Круглая галочка в строке: отмечает задачу прямо в виджете. Видимый круг меньше области нажатия.
struct CheckButton: View {
    let item: WidgetSnapshot.Item
    var size: CGFloat = 22
    var hitWidth: CGFloat = 40
    var hitHeight: CGFloat = 32

    var body: some View {
        let color = WidgetPalette.task(item)
        Button(intent: ToggleTaskIntent(id: item.id)) {
            ZStack {
                if item.isDone {
                    Circle().fill(WidgetPalette.accent)
                    Image(systemName: "checkmark")
                        .font(.system(size: size * 0.5, weight: .heavy))
                        .foregroundStyle(WidgetPalette.onAccent)
                } else {
                    Circle().strokeBorder(color, lineWidth: 2)
                    Circle().fill(color.opacity(0.12)).padding(2)
                }
            }
            .frame(width: size, height: size)
            .frame(width: hitWidth, height: hitHeight, alignment: .leading)
            .contentShape(Rectangle())
            .widgetAccentable()
        }
        .buttonStyle(.plain)
        .invalidatableContent()
        .accessibilityLabel(item.isDone ? "Вернуть «\(item.title)»" : "Отметить «\(item.title)» сделанной")
    }
}

/// Большая галочка с кольцом: у идущей задачи кольцо тает к её концу; у кончившейся — жёлтое «Готово?».
struct CheckRing: View {
    let item: WidgetSnapshot.Item
    /// Доля задачи впереди (0…1) или `nil` — кольцо целиком.
    var remaining: Double?
    var ask = false
    var size: CGFloat = 40
    var hit: CGFloat = 44

    var body: some View {
        let color = ask ? WidgetPalette.ask : WidgetPalette.task(item)
        Button(intent: ToggleTaskIntent(id: item.id)) {
            ZStack {
                Circle().stroke(color.opacity(0.25), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: max(0, min(1, remaining ?? 1)))
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Circle().fill(color.opacity(0.12)).padding(6)
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.38, weight: .bold))
                    .foregroundStyle(color.opacity(ask ? 1 : 0.75))
            }
            .padding(1.5)
            .frame(width: size, height: size)
            .frame(width: hit, height: hit)
            .contentShape(Rectangle())
            .widgetAccentable()
        }
        .buttonStyle(.plain)
        .invalidatableContent()
        .accessibilityLabel("Отметить «\(item.title)» сделанной")
    }
}

/// Огонёк серии. Горит — сегодня уже что-то сделано; контур — ещё нет (вечером — оранжевый: погаснет);
/// серии нет — серый контур без числа. С `ring` вокруг огонька кольцо прогресса дня.
struct FlameBadge: View {
    let state: DayState
    var ring = false

    var body: some View {
        let streak = state.snapshot.displayStreak
        let lit = state.flameLit
        let tint = lit || state.atRisk ? WidgetPalette.flame : WidgetPalette.muted
        HStack(spacing: 3) {
            ZStack {
                if ring {
                    Circle().stroke(WidgetPalette.track, lineWidth: 2.5)
                    Circle()
                        .trim(from: 0, to: max(0, min(1, state.snapshot.progress)))
                        .stroke(WidgetPalette.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                }
                Image(systemName: lit ? "flame.fill" : "flame")
                    .font(.system(size: ring ? 10 : 12, weight: .bold))
                    .foregroundStyle(tint)
                    .widgetAccentable()
            }
            .frame(width: ring ? 22 : 14, height: ring ? 22 : 14)
            if streak > 0 {
                Text("\(streak)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(lit ? WidgetPalette.flame : WidgetPalette.caption)
                    .contentTransition(.numericText(value: Double(streak)))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Серия \(WidgetText.days(streak))" + (lit ? "" : ", сегодня ещё ничего не сделано"))
    }
}

/// Счётчик просроченных: красная плашка «!3».
struct OverdueBadge: View {
    let count: Int

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: "exclamationmark")
                .font(.system(size: 10, weight: .heavy))
            Text("\(count)")
                .font(.system(size: 12, weight: .bold))
                .monospacedDigit()
        }
        .foregroundStyle(WidgetPalette.overdue)
        .padding(.horizontal, 7)
        .frame(height: 24)
        .background(WidgetPalette.overdue.opacity(0.16), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Просрочено: \(count), открыть")
    }
}

/// Круглая кнопка-ссылка в шапке: микрофон, плюс.
struct RoundLink: View {
    let destination: URL
    let systemImage: String
    var filled = false
    let label: String

    var body: some View {
        Link(destination: destination) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(filled ? WidgetPalette.onAccent : WidgetPalette.text)
                .frame(width: 30, height: 30)
                .background(filled ? WidgetPalette.accent : WidgetPalette.card, in: Circle())
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
                .widgetAccentable()
        }
        .accessibilityLabel(label)
    }
}

/// Живая полоска «сколько прошло» у идущей задачи: двигается сама, без перерисовки таймлайна.
struct LiveProgress: View {
    let interval: ClosedRange<Date>
    var tint: Color = WidgetPalette.accent

    var body: some View {
        ProgressView(timerInterval: interval, countsDown: false) {
            EmptyView()
        } currentValueLabel: {
            EmptyView()
        }
        .progressViewStyle(.linear)
        .tint(tint)
        .labelsHidden()
    }
}

/// «Вернуть»: последняя галочка из виджета, пока не прошли две минуты.
struct UndoRow: View {
    let item: WidgetSnapshot.Item
    let state: DayState

    var body: some View {
        // Эта галочка первой за день зажгла огонёк — сказать об этом.
        let lit = state.snapshot.doneTodayCount == 1
        Button(intent: ToggleTaskIntent(id: item.id)) {
            HStack(spacing: 4) {
                Image(systemName: lit ? "flame.fill" : "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(lit ? WidgetPalette.flame : WidgetPalette.accent)
                Text(lit ? "Горит · " + WidgetText.days(state.snapshot.displayStreak) : item.title)
                    .foregroundStyle(WidgetPalette.caption)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("вернуть")
                    .fontWeight(.semibold)
                    .foregroundStyle(WidgetPalette.accent)
                    .fixedSize()
            }
            .font(.system(size: 12))
            .frame(maxWidth: .infinity, minHeight: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Вернуть «\(item.title)»")
    }
}

/// Вечер без единой галочки: «погаснет через 5:12:09».
struct AtRiskRow: View {
    let state: DayState
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "flame")
                .font(.system(size: 11, weight: .bold))
            Text(compact ? "погаснет" : "\(state.snapshot.displayStreak) · погаснет через")
                .lineLimit(1)
            Countdown(from: state.date, to: state.midnight, font: .system(size: 12, weight: .semibold),
                      color: WidgetPalette.flame, width: 54, leading: true)
            Spacer(minLength: 0)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(WidgetPalette.flame)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Серия погаснет в полночь")
    }
}

/// Неделя серии: понедельник…воскресенье, закрытые дни — огоньком, сегодня — кольцом.
struct WeekDots: View {
    let state: DayState

    var body: some View {
        let week = state.snapshot.displayWeek() ?? Array(repeating: false, count: 7)
        let today = WidgetSnapshot.weekIndex(of: state.snapshot.day)
        HStack(spacing: 5) {
            ForEach(0..<7, id: \.self) { index in
                Circle()
                    .fill(week[index] ? WidgetPalette.flame : Color.white.opacity(index < today ? 0.14 : 0.06))
                    .overlay {
                        if index == today && !week[index] {
                            Circle().strokeBorder(WidgetPalette.flame, lineWidth: 1.5)
                        }
                    }
                    .frame(width: 9, height: 9)
                    .widgetAccentable(week[index])
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("На этой неделе закрыто дней: \(week.filter { $0 }.count) из 7")
    }
}

/// Полоска дня: задачи с временем цветными отрезками, отметка «сейчас», часы под ней.
struct DayStrip: View {
    let state: DayState

    var body: some View {
        let bounds = state.snapshot.timelineBounds(at: state.minutes)
        let span = CGFloat(max(60, bounds.upperBound - bounds.lowerBound))
        // Подписи часов, кратных трём: 9, 12, 15…
        let firstHour = ((bounds.lowerBound + 59) / 60 + 2) / 3 * 3
        let hours = Array(stride(from: firstHour, through: bounds.upperBound / 60, by: 3))
        GeometryReader { geometry in
            let width = geometry.size.width
            let x: (Int) -> CGFloat = { minutes in width * CGFloat(minutes - bounds.lowerBound) / span }
            ZStack(alignment: .topLeading) {
                Capsule()
                    .fill(WidgetPalette.track)
                    .frame(width: width, height: 8)
                    .offset(y: 3)
                ForEach(state.snapshot.items.filter { $0.start != nil }) { item in
                    let start = item.start ?? 0
                    RoundedRectangle(cornerRadius: 2)
                        .fill(WidgetPalette.task(item).opacity(item.isDone ? 0.35 : 1))
                        .frame(width: max(3, x(start + item.duration) - x(start)), height: 8)
                        .offset(x: x(start), y: 3)
                }
                RoundedRectangle(cornerRadius: 1)
                    .fill(WidgetPalette.text)
                    .frame(width: 2, height: 14)
                    .offset(x: min(width - 2, max(0, x(state.minutes) - 1)))
                    .widgetAccentable()
                ForEach(hours, id: \.self) { hour in
                    Text("\(hour)")
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(WidgetPalette.muted)
                        .fixedSize()
                        .frame(width: 24)
                        .offset(x: min(width - 24, max(0, x(hour * 60) - 12)), y: 16)
                }
            }
        }
        .frame(height: 30)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("План дня, сейчас \(ClockGrid.format(minutes: state.minutes))")
    }
}

/// Фон: тёмный градиент; в цветном режиме — мягкая подсветка по состоянию дня.
struct WidgetBackground: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let glow: Color?

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x121316), Color(hex: 0x1A1B1E)], startPoint: .top, endPoint: .bottom)
            if let glow, renderingMode == .fullColor {
                RadialGradient(colors: [glow.opacity(0.18), .clear], center: .topLeading, startRadius: 0, endRadius: 170)
            }
        }
    }
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
