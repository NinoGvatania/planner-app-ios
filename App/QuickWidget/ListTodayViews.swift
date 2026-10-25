import PlannerCore
import SwiftUI
import WidgetKit

// MARK: - Средний

/// Средний: список как у Todoist — галочки прямо в виджете, время справа (у идущей — живой отсчёт),
/// микрофон и «плюс» в шапке.
struct MediumTodayView: View {
    let state: DayState?

    var body: some View {
        if let state {
            VStack(alignment: .leading, spacing: 4) {
                ListHeader(state: state, large: false)
                if state.focus != nil {
                    // Четыре строки, на экране поменьше — сколько влезет.
                    ViewThatFits(in: .vertical) {
                        TaskList(state: state, rows: state.rows(limit: 4), rowHeight: 26)
                        TaskList(state: state, rows: state.rows(limit: 3), rowHeight: 26)
                        TaskList(state: state, rows: state.rows(limit: 2), rowHeight: 26)
                    }
                } else if state.allDone {
                    doneBody(state)
                } else {
                    emptyBody(state)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetURL(DeepLink.today)
        } else {
            NoSnapshotView()
        }
    }

    /// Всё сделано: огонёк и серия, под ними — просроченные или завтра, сколько влезет.
    private func doneBody(_ state: DayState) -> some View {
        ViewThatFits(in: .vertical) {
            doneBody(state, rows: 2)
            doneBody(state, rows: 1)
            doneBody(state, rows: 0)
        }
    }

    private func doneBody(_ state: DayState, rows: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Celebration(state: state, compact: true)
            if rows > 0 && !state.overdue.isEmpty {
                TaskList(state: state, rows: Array(state.overdue.prefix(rows)), rowHeight: 26)
            } else if rows > 0 && !state.tomorrow.isEmpty {
                TomorrowPreview(items: Array(state.tomorrow.prefix(rows)))
            }
        }
    }

    /// Пустой день: что можно сделать; бэклог и завтра — если влезают.
    private func emptyBody(_ state: DayState) -> some View {
        ViewThatFits(in: .vertical) {
            emptyBody(state, tomorrow: true)
            emptyBody(state, tomorrow: false)
        }
    }

    private func emptyBody(_ state: DayState, tomorrow: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("На сегодня пусто")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(WidgetPalette.text)
            Text("Нажми ＋ или скажи голосом")
                .font(.system(size: 12))
                .foregroundStyle(WidgetPalette.caption)
            if state.snapshot.backlog > 0 {
                Link(destination: DeepLink.backlog) {
                    Text("В бэклоге \(state.snapshot.backlog) ›")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(WidgetPalette.accent)
                        .frame(height: 28)
                }
            }
            if tomorrow && !state.tomorrow.isEmpty {
                TomorrowPreview(items: Array(state.tomorrow.prefix(1)))
            }
        }
    }
}

// MARK: - Большой

/// Большой: шапка, полоска дня, карточка «сейчас» с большой галочкой и живым временем, дальше —
/// список с галочками, внизу — серия, «Просрочено» с «На сегодня» и бэклог.
struct LargeTodayView: View {
    let state: DayState?

    var body: some View {
        if let state {
            let focus = state.focus
            let hasTimed = state.snapshot.items.contains { $0.start != nil }
            VStack(alignment: .leading, spacing: 8) {
                ListHeader(state: state, large: true)
                if hasTimed {
                    DayStrip(state: state)
                        .opacity(state.allDone ? 0.5 : 1)
                }
                if let focus {
                    NowCard(item: focus, state: state)
                } else if state.allDone {
                    Celebration(state: state, compact: false)
                } else {
                    EmptyDayCard(backlog: state.snapshot.backlog)
                }
                // Сколько строк влезет под карточку (у неё бывает одна строка названия, бывает две).
                ViewThatFits(in: .vertical) {
                    list(state, focus: focus, limit: 5)
                    list(state, focus: focus, limit: 4)
                    list(state, focus: focus, limit: 3)
                    list(state, focus: focus, limit: 2)
                    list(state, focus: focus, limit: 1)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .widgetURL(DeepLink.today)
        } else {
            NoSnapshotView()
        }
    }

    /// Список под карточкой и подвал. Без главной задачи (всё сделано, пусто) — просроченные и завтра.
    private func list(_ state: DayState, focus: WidgetSnapshot.Item?, limit: Int) -> some View {
        let rows = focus == nil ? Array(state.overdue.prefix(limit)) : state.rows(limit: limit, skipping: focus?.id)
        let tomorrow = rows.count < limit - 1 ? Array(state.tomorrow.prefix(limit - 1 - rows.count)) : []
        return VStack(alignment: .leading, spacing: 6) {
            if !rows.isEmpty {
                TaskList(state: state, rows: rows, rowHeight: 30)
            }
            if !tomorrow.isEmpty {
                TomorrowPreview(items: tomorrow)
            }
            Spacer(minLength: 0)
            LargeFooter(state: state, hidden: state.hiddenOpen(shown: rows, skipping: focus?.id))
        }
    }
}

/// Подвал большого: слева — что важнее всего (серия гаснет, просроченные с «На сегодня», что не влезло,
/// неделя серии), справа — бэклог.
struct LargeFooter: View {
    let state: DayState
    let hidden: Int

    var body: some View {
        HStack(spacing: 8) {
            if state.atRisk {
                AtRiskRow(state: state)
            } else if state.snapshot.overdue > 0 {
                Link(destination: DeepLink.overdue) {
                    Text("Просрочено \(state.snapshot.overdue) ›")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WidgetPalette.overdue)
                        .frame(height: 28)
                }
                Button(intent: MoveOverdueToTodayIntent()) {
                    Text("На сегодня")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(WidgetPalette.accent)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(WidgetPalette.accent.opacity(0.15), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Все просроченные — на сегодня, на весь день")
            } else if hidden > 0 {
                Text("ещё \(hidden) " + WidgetText.plural(hidden, "задача", "задачи", "задач"))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(WidgetPalette.caption)
            } else {
                WeekDots(state: state)
                if let best = state.snapshot.bestStreak, best > 0 {
                    Text("рекорд \(best)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(WidgetPalette.caption)
                }
            }
            Spacer(minLength: 4)
            if state.snapshot.backlog > 0 {
                Link(destination: DeepLink.backlog) {
                    Text("Бэклог \(state.snapshot.backlog) ›")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(WidgetPalette.caption)
                        .frame(height: 28)
                }
            }
        }
        .lineLimit(1)
        .frame(height: 28)
    }
}

// MARK: - Части

/// Шапка списка: «Сегодня» и сделано из скольких (в большом — дата), просроченные, огонёк с кольцом
/// прогресса дня, микрофон и «плюс».
struct ListHeader: View {
    let state: DayState
    let large: Bool

    var body: some View {
        let snapshot = state.snapshot
        HStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Сегодня")
                    .font(.system(size: large ? 22 : 17, weight: .bold))
                    .foregroundStyle(WidgetPalette.text)
                    .fixedSize()
                Text(large ? WidgetText.dayTitle(state.date) : (snapshot.items.isEmpty ? "" : "\(snapshot.doneCount) из \(snapshot.items.count)"))
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(WidgetPalette.caption)
                    .lineLimit(1)
                    .contentTransition(.numericText())
            }
            Spacer(minLength: 4)
            if !large && snapshot.overdue > 0 {
                Link(destination: DeepLink.overdue) {
                    OverdueBadge(count: snapshot.overdue)
                }
            }
            Link(destination: DeepLink.streak) {
                FlameBadge(state: state, ring: true)
                    .frame(height: 30)
            }
            RoundLink(destination: DeepLink.voice, systemImage: "mic.fill", label: "Сказать задачу")
            RoundLink(destination: DeepLink.add, systemImage: "plus", filled: true, label: "Добавить задачу")
        }
        .frame(height: 30)
    }
}

/// Строки задач с тонкими разделителями.
struct TaskList: View {
    let state: DayState
    let rows: [WidgetSnapshot.Item]
    let rowHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Rectangle()
                        .fill(WidgetPalette.line)
                        .frame(height: 0.5)
                        .padding(.leading, 40)
                }
                TaskListRow(item: item, state: state, height: rowHeight)
            }
        }
    }
}

/// Строка: галочка, название (тап — открыть задачу), справа — время, живой отсчёт или «готово?».
struct TaskListRow: View {
    let item: WidgetSnapshot.Item
    let state: DayState
    let height: CGFloat

    var body: some View {
        let timing = state.timing(item)
        let running: Bool = {
            if case .now = timing { return true }
            return false
        }()
        HStack(spacing: 0) {
            CheckButton(item: item, size: 22, hitWidth: 40, hitHeight: height)
            Link(destination: DeepLink.task(item.id)) {
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title)
                            .font(.system(size: 15, weight: running ? .semibold : .regular))
                            .strikethrough(item.isDone, color: WidgetPalette.muted)
                            .foregroundStyle(item.isDone ? WidgetPalette.muted : WidgetPalette.text)
                            .lineLimit(1)
                        if running, let interval = state.interval(item) {
                            LiveProgress(interval: interval)
                        }
                    }
                    Spacer(minLength: 6)
                    trailing(timing)
                }
                .padding(.trailing, running ? 8 : 0)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
        }
        .frame(height: height)
        .background {
            if running {
                RoundedRectangle(cornerRadius: 8).fill(WidgetPalette.accent.opacity(0.10))
            }
        }
    }

    @ViewBuilder
    private func trailing(_ timing: WidgetTiming) -> some View {
        switch timing {
        case .now:
            HStack(spacing: 3) {
                Text("ещё")
                Countdown(from: state.date, to: state.moment((item.start ?? 0) + item.duration),
                          font: .system(size: 13, weight: .semibold), color: WidgetPalette.accent, width: 52)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(WidgetPalette.accent)
        case .later(let minutes) where minutes <= 60:
            HStack(spacing: 3) {
                Text("через")
                Countdown(from: state.date, to: state.moment(item.start ?? 0),
                          font: .system(size: 13, weight: .semibold), color: WidgetPalette.text, width: 52)
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(WidgetPalette.text)
        default:
            if let label = WidgetText.trailing(item, timing: timing, state: state) {
                Text(label.text)
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(label.color)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
    }
}

/// Главная задача большого виджета: большая галочка, что это и когда, справа — время крупно.
struct NowCard: View {
    let item: WidgetSnapshot.Item
    let state: DayState

    var body: some View {
        let hero = FocusHero(state: state, item: item)
        HStack(spacing: 10) {
            CheckRing(item: item, remaining: state.remaining(item), ask: hero.ask)
            VStack(alignment: .leading, spacing: 2) {
                Text(hero.label)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.3)
                    .foregroundStyle(hero.labelColor)
                    .lineLimit(1)
                Link(destination: DeepLink.task(item.id)) {
                    Text(item.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(WidgetPalette.text)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text(hero.meta)
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(WidgetPalette.caption)
                    .lineLimit(1)
            }
            VStack(alignment: .trailing, spacing: 0) {
                hero.value(from: state.date, width: 88, large: 24, small: 20, leading: false)
                if !hero.caption.isEmpty {
                    Text(hero.caption)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(WidgetPalette.caption)
                        .lineLimit(1)
                }
            }
            .frame(width: 88, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 16).fill(WidgetPalette.card)
                RoundedRectangle(cornerRadius: 16).fill(WidgetPalette.task(item).opacity(0.14))
            }
        }
    }
}

/// «Всё сделано»: большой огонёк, сколько сделано и серия (в большом — с неделей).
struct Celebration: View {
    let state: DayState
    let compact: Bool

    var body: some View {
        let streak = state.snapshot.displayStreak
        let record = streak >= 3 && streak >= (state.snapshot.bestStreak ?? .max)
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(WidgetPalette.flame.opacity(0.16))
                Image(systemName: "flame.fill")
                    .font(.system(size: compact ? 24 : 30, weight: .bold))
                    .foregroundStyle(WidgetPalette.flameGradient)
                    .widgetAccentable()
            }
            .frame(width: compact ? 46 : 56, height: compact ? 46 : 56)
            VStack(alignment: .leading, spacing: 3) {
                Text("Всё сделано")
                    .font(.system(size: compact ? 17 : 22, weight: .bold))
                    .foregroundStyle(WidgetPalette.text)
                Text(record ? "Новый рекорд — " + WidgetText.days(streak) + "!"
                     : "\(state.snapshot.doneCount) из \(state.snapshot.items.count) · " + WidgetText.days(streak) + " подряд")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(WidgetPalette.flame)
                    .lineLimit(1)
                if !compact {
                    WeekDots(state: state)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(compact ? 0 : 12)
        .background {
            if !compact {
                RoundedRectangle(cornerRadius: 16)
                    .fill(LinearGradient(colors: [Color(hex: 0x3A2410), Color(hex: 0x1F2024)], startPoint: .topLeading, endPoint: .bottomTrailing))
            }
        }
    }
}

/// Пустой день в большом виджете: сказать задачу или взять из бэклога.
struct EmptyDayCard: View {
    let backlog: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Чистый день")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(WidgetPalette.text)
            Text("Скажи задачу или возьми из бэклога")
                .font(.system(size: 12))
                .foregroundStyle(WidgetPalette.caption)
                .lineLimit(1)
            HStack(spacing: 8) {
                action("Сказать", systemImage: "mic.fill", destination: DeepLink.voice, filled: false)
                if backlog > 0 {
                    action("Бэклог · \(backlog)", systemImage: "tray.full.fill", destination: DeepLink.backlog, filled: true)
                } else {
                    action("Добавить", systemImage: "plus", destination: DeepLink.add, filled: true)
                }
            }
            .padding(.top, 2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WidgetPalette.card, in: RoundedRectangle(cornerRadius: 16))
    }

    private func action(_ title: String, systemImage: String, destination: URL, filled: Bool) -> some View {
        Link(destination: destination) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(filled ? WidgetPalette.onAccent : WidgetPalette.text)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .background(filled ? WidgetPalette.accent : WidgetPalette.track, in: Capsule())
        }
    }
}

/// «Завтра»: первые задачи следующего дня (без галочек — их отмечают в свой день; тап — открыть).
struct TomorrowPreview: View {
    let items: [WidgetSnapshot.Item]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("ЗАВТРА")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(WidgetPalette.muted)
                .frame(height: 16)
            ForEach(items) { item in
                Link(destination: DeepLink.task(item.id)) {
                    HStack(spacing: 6) {
                        Circle()
                            .strokeBorder(WidgetPalette.task(item), lineWidth: 1.5)
                            .frame(width: 7, height: 7)
                        Text(item.start.map { ClockGrid.format(minutes: $0) } ?? "день")
                            .font(.system(size: 12, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(WidgetPalette.caption)
                            .frame(width: 38, alignment: .leading)
                        Text(item.title)
                            .font(.system(size: 13))
                            .foregroundStyle(WidgetPalette.text.opacity(0.6))
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .frame(height: 22)
                    .contentShape(Rectangle())
                }
            }
        }
    }
}

/// Снимка ещё нет: приложение не открывали после установки.
struct NoSnapshotView: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(WidgetPalette.accent)
            Text("Открой Quick")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(WidgetPalette.text)
            Text("и здесь появится план дня")
                .font(.system(size: 13))
                .foregroundStyle(WidgetPalette.caption)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .widgetURL(DeepLink.today)
    }
}
