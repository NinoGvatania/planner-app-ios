import PlannerCore
import SwiftUI

/// Один месяц: сетка недель с понедельника, всегда шесть строк, в клетке — число и чипы задач по цвету.
/// Тап по дню открывает его, удержание на пустом месте создаёт задачу на этот день, удержание чипа —
/// перенос, каждая клетка — зона сброса (задача переезжает на этот день, время сохраняется).
/// Листание месяцев делает `PagerView` снаружи.
struct MonthView: View {
    /// Любой день нужного месяца.
    let anchor: Date
    let tasks: [PlannerTask]
    let drag: DragState?
    var live = true
    let onSelectDay: (Int) -> Void
    let onEdit: (PlannerTask) -> Void
    let onCreate: (Int) -> Void
    let onDragChanged: (PlannerTask, CGPoint, CGPoint) -> Void
    let onDragEnded: () -> Void
    var onDragCancelled: (() -> Void)? = nil

    /// День, на котором уже создали задачу этим удержанием (чтобы не создавать второй раз).
    @State private var creatingDay: Int?

    private var monthStart: Date { DayMath.monthStart(of: anchor) }
    private var monthIndex: Int { DayMath.monthIndex(monthStart) }

    /// Недели месяца как смещения дней от сегодняшнего: всегда шесть строк, чтобы сетка не прыгала.
    private var weeks: [[Int]] {
        let first = DayMath.offset(of: monthStart)
        let gridStart = DayMath.weekStartOffset(containing: first)
        return (0..<6).map { row in (0..<7).map { gridStart + row * 7 + $0 } }
    }

    private var tasksByDay: [Date: [PlannerTask]] {
        var result: [Date: [PlannerTask]] = [:]
        for task in tasks {
            guard let day = task.day else { continue }
            result[day, default: []].append(task)
        }
        for key in result.keys {
            result[key]?.sort { a, b in
                if a.isDone != b.isDone { return !a.isDone }
                return (a.start ?? -1) < (b.start ?? -1)
            }
        }
        return result
    }

    var body: some View {
        let byDay = tasksByDay
        VStack(spacing: 0) {
            weekdayHeader
            Rectangle().fill(Tokens.line).frame(height: 1)
            GeometryReader { geometry in
                let rows = weeks
                let cellHeight = geometry.size.height / CGFloat(max(1, rows.count))
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, week in
                        HStack(spacing: 0) {
                            ForEach(week, id: \.self) { offset in
                                cell(offset: offset, height: cellHeight, tasks: byDay[DayMath.day(offset: offset)] ?? [])
                            }
                        }
                        .frame(height: cellHeight)
                        .overlay(alignment: .bottom) { Rectangle().fill(Tokens.line).frame(height: 1) }
                    }
                }
            }
        }
        .padding(.horizontal, 6)
    }

    /// Подписи дней недели; по краям — стрелки-намёк, что месяцы листаются (места не занимают).
    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { column in
                Text(DayMath.weekdayShort[(column + 1) % 7])
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(column >= 5 ? Tokens.muted : Tokens.caption)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 22)
        .overlay(alignment: .leading) {
            Image(systemName: "chevron.left")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Tokens.muted.opacity(0.7))
                .padding(.leading, 2)
        }
        .overlay(alignment: .trailing) {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Tokens.muted.opacity(0.7))
                .padding(.trailing, 2)
        }
        .accessibilityHint("Свайп влево или вправо листает месяцы")
    }

    /// Сколько фишек влезает в клетку: под числом (3 + 24 pt) по 21 pt на фишку, 4 pt запаса снизу.
    /// При открытом бэклоге клетки низкие — тогда фишек нет, а число задач стоит рядом с числом дня.
    private func chipSlots(height: CGFloat) -> Int {
        max(0, Int((height - 3 - 24 - 4) / 21))
    }

    private func cell(offset: Int, height: CGFloat, tasks: [PlannerTask]) -> some View {
        let date = DayMath.day(offset: offset)
        let inMonth = DayMath.monthIndex(date) == monthIndex
        let today = offset == 0
        let weekend = DayMath.weekdayIndex(date) == 0 || DayMath.weekdayIndex(date) == 6
        let hovered = live && drag?.target == .dayTab(offset: offset)
        let slots = chipSlots(height: height)
        // Не влезают все — последняя строка отдаётся под «+N» (14 pt вместо 21).
        let shown = Array(tasks.prefix(tasks.count > slots ? max(0, slots - 1) : slots))
        let hidden = tasks.count - shown.count
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text("\(DayMath.dayOfMonth(date))")
                    .font(.system(size: 13, weight: today ? .bold : .semibold))
                    .monospacedDigit()
                    .foregroundStyle(today ? Tokens.onAccent : (inMonth ? (weekend ? Tokens.caption : Tokens.text) : Tokens.muted.opacity(0.6)))
                    .frame(width: 24, height: 24)
                    .background(today ? Tokens.accent : Color.clear, in: Circle())
                    .padding(.leading, 2)
                Spacer(minLength: 0)
                if slots == 0, !tasks.isEmpty {
                    Text("\(tasks.count)")
                        .font(.system(size: 11, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(Tokens.caption)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 18, minHeight: 16)
                        .background(Tokens.badge, in: Capsule())
                        .padding(.trailing, 2)
                }
            }
            .contentShape(Rectangle())
            .gesture(createHold(offset))
            ForEach(shown, id: \.id) { task in
                chip(task)
            }
            if hidden > 0, slots > 0 {
                Text("+\(hidden)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Tokens.muted)
                    .frame(height: 14)
                    .padding(.leading, 4)
            }
            // Пустой остаток клетки (и строка с числом): удержание здесь создаёт задачу, по фишкам — тянет их.
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(createHold(offset))
        }
        // В низкой клетке (открыт бэклог) верхний отступ уступает место кружку с числом.
        .padding(.top, min(3, max(0, height - 24)))
        .padding(.horizontal, 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Ничего из клетки не вылезает в соседнюю неделю, даже пока высота анимируется.
        .clipped()
        .background(hovered ? Tokens.accent.opacity(0.16) : (inMonth ? Color.clear : Color.white.opacity(0.015)))
        .overlay(alignment: .trailing) { Rectangle().fill(Tokens.line.opacity(0.6)).frame(width: 1) }
        .contentShape(Rectangle())
        .onTapGesture { onSelectDay(offset) }
        .reportZone("tab-\(offset)", enabled: live)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DayMath.accessibilityLabel(offset: offset) + ", задач: \(tasks.count)")
        .accessibilityHint("Удержание создаёт задачу")
    }

    /// Удержание на пустом месте клетки: одна задача «на весь день» за одно удержание, название спросит экран.
    private func createHold(_ offset: Int) -> some UIGestureRecognizerRepresentable {
        HoldDragGesture(onChanged: { _, _ in
            guard creatingDay != offset else { return }
            creatingDay = offset
            onCreate(offset)
        }, onEnded: {
            creatingDay = nil
        }, onCancelled: {
            creatingDay = nil
        })
    }

    private func chip(_ task: PlannerTask) -> some View {
        let style = task.style
        return Text(task.title)
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)
            .strikethrough(task.isDone)
            .foregroundStyle(style.text)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 17)
            .background(style.background, in: RoundedRectangle(cornerRadius: 4))
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1).fill(style.dot).frame(width: 2).padding(.vertical, 2)
            }
            .opacity(drag?.taskID == task.id ? 0.35 : (task.isDone ? 0.5 : 1))
            // Фишка 17 pt, зона нажатия 21 pt: промах по высоте не создаёт новую задачу.
            .padding(.vertical, 2)
            .contentShape(Rectangle())
            .onTapGesture { onEdit(task) }
            .gesture(HoldDragGesture(onChanged: { location, start in onDragChanged(task, location, start) }, onEnded: onDragEnded, onCancelled: onDragCancelled ?? onDragEnded))
    }
}
