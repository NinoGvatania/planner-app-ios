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

    private func cell(offset: Int, height: CGFloat, tasks: [PlannerTask]) -> some View {
        let date = DayMath.day(offset: offset)
        let inMonth = DayMath.monthIndex(date) == monthIndex
        let today = offset == 0
        let weekend = DayMath.weekdayIndex(date) == 0 || DayMath.weekdayIndex(date) == 6
        let hovered = live && drag?.target == .dayTab(offset: offset)
        let maxChips = max(1, Int((height - 30) / 19))
        let shown = Array(tasks.prefix(tasks.count > maxChips ? maxChips - 1 : maxChips))
        let hidden = tasks.count - shown.count
        return VStack(alignment: .leading, spacing: 2) {
            Text("\(DayMath.dayOfMonth(date))")
                .font(.system(size: 13, weight: today ? .bold : .semibold))
                .monospacedDigit()
                .foregroundStyle(today ? Tokens.onAccent : (inMonth ? (weekend ? Tokens.caption : Tokens.text) : Tokens.muted.opacity(0.6)))
                .frame(width: 24, height: 24)
                .background(today ? Tokens.accent : Color.clear, in: Circle())
                .padding(.leading, 2)
            ForEach(shown, id: \.id) { task in
                chip(task)
            }
            if hidden > 0 {
                Text("+\(hidden)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Tokens.muted)
                    .padding(.leading, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 3)
        .padding(.horizontal, 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(hovered ? Tokens.accent.opacity(0.16) : (inMonth ? Color.clear : Color.white.opacity(0.015)))
        .overlay(alignment: .trailing) { Rectangle().fill(Tokens.line.opacity(0.6)).frame(width: 1) }
        .contentShape(Rectangle())
        .onTapGesture { onSelectDay(offset) }
        .gesture(
            HoldDragGesture(onChanged: { _, _ in
                // Удержание на дне: одна задача «на весь день» за одно удержание, название спросит экран.
                guard creatingDay != offset else { return }
                creatingDay = offset
                onCreate(offset)
            }, onEnded: {
                creatingDay = nil
            }, onCancelled: {
                creatingDay = nil
            })
        )
        .reportZone("tab-\(offset)", enabled: live)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DayMath.accessibilityLabel(offset: offset) + ", задач: \(tasks.count)")
        .accessibilityHint("Удержание создаёт задачу")
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
            .contentShape(Rectangle())
            .onTapGesture { onEdit(task) }
            .gesture(HoldDragGesture(onChanged: { location, start in onDragChanged(task, location, start) }, onEnded: onDragEnded, onCancelled: onDragCancelled ?? onDragEnded))
    }
}
