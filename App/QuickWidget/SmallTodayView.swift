import PlannerCore
import SwiftUI
import WidgetKit

/// Маленький виджет — главный: что сейчас (время крупно, живым отсчётом), большая галочка с тающим
/// кольцом, название и что дальше — две-три задачи; сверху — огонёк серии.
struct SmallTodayView: View {
    let state: DayState?

    var body: some View {
        if let state {
            if let focus = state.focus {
                focusView(state, focus)
            } else if state.allDone {
                doneView(state)
            } else {
                emptyView(state)
            }
        } else {
            noData
        }
    }

    // MARK: - Есть что делать

    private func focusView(_ state: DayState, _ item: WidgetSnapshot.Item) -> some View {
        let hero = FocusHero(state: state, item: item)
        return VStack(alignment: .leading, spacing: 0) {
            header(hero.label, color: hero.labelColor, state: state)
            HStack(alignment: .center, spacing: 2) {
                VStack(alignment: .leading, spacing: 0) {
                    hero.value(from: state.date, width: 92, large: 28, small: 24)
                    Text(hero.meta)
                        .font(.system(size: 11, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(WidgetPalette.caption)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                CheckRing(item: item, remaining: state.remaining(item), ask: hero.ask)
                    .padding(.trailing, -2)
            }
            .frame(height: 46)
            .padding(.top, 4)
            // Название и строки «дальше»: сколько влезет — длинное название забирает строку.
            ViewThatFits(in: .vertical) {
                lower(state, item, hero: hero, titleLines: 2, slots: 3)
                lower(state, item, hero: hero, titleLines: 2, slots: 2)
                lower(state, item, hero: hero, titleLines: 1, slots: 2)
                lower(state, item, hero: hero, titleLines: 1, slots: 1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(state.agenda.isEmpty ? DeepLink.overdue : DeepLink.today)
    }

    private func lower(_ state: DayState, _ item: WidgetSnapshot.Item, hero: FocusHero, titleLines: Int, slots: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(item.title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WidgetPalette.text)
                .lineLimit(titleLines)
                .padding(.top, 4)
            Spacer(minLength: 4)
            bottom(state, skipping: item.id, slots: slots, riskShown: hero.countdownTo == state.midnight)
        }
    }

    /// Нижние строки: «Вернуть» после галочки, следующие задачи (сегодня, потом просроченные, потом
    /// завтра), вечером — «погаснет через…».
    private func bottom(_ state: DayState, skipping skipped: UUID?, slots: Int, riskShown: Bool) -> some View {
        // Каждая строка занимает место: «вернуть» — первое, «погаснет» — последнее, задачи — что осталось.
        let undo = slots >= 1 ? state.justDone : nil
        let used = undo == nil ? 0 : 1
        let risk = state.atRisk && !riskShown && slots - used >= 1
        let free = max(0, slots - used - (risk ? 1 : 0))
        let next = (state.agenda + state.overdue).filter { $0.id != skipped }
        let shown = Array(next.prefix(free))
        let tomorrow = shown.isEmpty ? Array(state.tomorrow.prefix(free)) : []
        return VStack(alignment: .leading, spacing: 2) {
            if let undo {
                UndoRow(item: undo, state: state)
            }
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, task in
                NextRow(item: task, state: state, more: index == shown.count - 1 ? next.count - shown.count : 0)
            }
            ForEach(Array(tomorrow.enumerated()), id: \.element.id) { index, task in
                NextRow(item: task, state: state, tomorrow: true, first: index == 0)
            }
            if risk {
                AtRiskRow(state: state, compact: true)
            }
        }
    }

    private func header(_ label: String, color: Color, state: DayState, flame: Bool = true) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 11, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(color)
                .lineLimit(1)
            Spacer(minLength: 4)
            if flame {
                FlameBadge(state: state)
            }
        }
        .frame(height: 16)
    }

    // MARK: - Всё сделано

    private func doneView(_ state: DayState) -> some View {
        let streak = state.snapshot.displayStreak
        let record = streak >= 3 && streak >= (state.snapshot.bestStreak ?? .max)
        return VStack(alignment: .leading, spacing: 0) {
            header("ДЕНЬ ЗАКРЫТ", color: WidgetPalette.accent, state: state, flame: false)
            HStack(spacing: 8) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(WidgetPalette.flameGradient)
                    .widgetAccentable()
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(streak)")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(WidgetPalette.flame)
                        .contentTransition(.numericText(value: Double(streak)))
                    Text(record ? "Рекорд!" : WidgetText.plural(streak, "день", "дня", "дней") + " подряд")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(record ? WidgetPalette.flame : WidgetPalette.caption)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(height: 46)
            .padding(.top, 4)
            // Подпись и строки под ней: «вернуть» и завтра — сколько влезет.
            ViewThatFits(in: .vertical) {
                doneLower(state, slots: 2)
                doneLower(state, slots: 1)
                doneLower(state, slots: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(state.overdue.isEmpty ? DeepLink.today : DeepLink.overdue)
    }

    private func doneLower(_ state: DayState, slots: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Всё сделано · \(state.snapshot.doneCount) из \(state.snapshot.items.count)")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(WidgetPalette.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.top, 4)
            Spacer(minLength: 4)
            if !state.overdue.isEmpty {
                Text("Просрочено \(state.overdue.count) — разобрать ›")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(WidgetPalette.overdue)
                    .lineLimit(2)
            } else {
                bottom(state, skipping: nil, slots: slots, riskShown: false)
            }
        }
    }

    // MARK: - Пустой день

    private func emptyView(_ state: DayState) -> some View {
        let backlog = state.snapshot.backlog
        return VStack(alignment: .leading, spacing: 0) {
            header("СЕГОДНЯ ПУСТО", color: WidgetPalette.caption, state: state)
            HStack(spacing: 4) {
                Text("Чистый день")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(WidgetPalette.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(WidgetPalette.onAccent)
                    .frame(width: 40, height: 40)
                    .background(WidgetPalette.accent, in: Circle())
                    .widgetAccentable()
            }
            .frame(height: 46)
            .padding(.top, 4)
            // Подсказка не режется: строки «вернуть» и завтра уступают ей место.
            ViewThatFits(in: .vertical) {
                emptyLower(state, slots: 2)
                emptyLower(state, slots: 1)
                emptyLower(state, slots: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(backlog > 0 ? DeepLink.backlog : DeepLink.add)
    }

    private func emptyLower(_ state: DayState, slots: Int) -> some View {
        let backlog = state.snapshot.backlog
        return VStack(alignment: .leading, spacing: 0) {
            Text(backlog > 0 ? "В бэклоге \(backlog) — возьми одну" : "Добавь первую задачу")
                .font(.system(size: 12))
                .foregroundStyle(WidgetPalette.caption)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
            Spacer(minLength: 4)
            bottom(state, skipping: nil, slots: slots, riskShown: false)
        }
    }

    private var noData: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(WidgetPalette.accent)
            Spacer(minLength: 0)
            Text("Открой Quick")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(WidgetPalette.text)
            Text("и здесь появится план дня")
                .font(.system(size: 12))
                .foregroundStyle(WidgetPalette.caption)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .widgetURL(DeepLink.today)
    }
}

/// Строка «дальше» маленького виджета: точка цвета задачи, время (у просроченной — красный день), название.
struct NextRow: View {
    let item: WidgetSnapshot.Item
    let state: DayState
    var more = 0
    var tomorrow = false
    var first = false

    var body: some View {
        let time: (text: String, color: Color) = {
            if case .overdue(let day) = state.timing(item) {
                return (WidgetText.overdueDay(day, today: state.snapshot.day), WidgetPalette.overdue)
            }
            let color = tomorrow ? WidgetPalette.muted : WidgetPalette.text.opacity(0.8)
            return (item.start.map { ClockGrid.format(minutes: $0) } ?? "день", color)
        }()
        HStack(spacing: 5) {
            Group {
                if tomorrow {
                    Circle().strokeBorder(WidgetPalette.task(item), lineWidth: 1.5)
                } else {
                    Circle().fill(WidgetPalette.task(item))
                }
            }
            .frame(width: 6, height: 6)
            // Время — в колонке 36 pt; дата просроченной («21 июн») шире — колонка растёт под неё.
            Text(time.text)
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(time.color)
                .lineLimit(1)
                .fixedSize()
                .frame(minWidth: 36, alignment: .leading)
            Text((tomorrow && first ? "завтра · " : "") + item.title)
                .font(.system(size: 12))
                .foregroundStyle(tomorrow ? WidgetPalette.muted : WidgetPalette.caption)
                .lineLimit(1)
            Spacer(minLength: 0)
            if more > 0 {
                Text("+\(more)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(WidgetPalette.muted)
                    .fixedSize()
            }
        }
        .frame(height: 15)
    }
}
