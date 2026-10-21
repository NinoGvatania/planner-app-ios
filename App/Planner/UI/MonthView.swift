import PlannerCore
import SwiftUI

/// Месяц: сетка недель с понедельника, всегда шесть строк, в клетке — число и чипы задач по цвету.
/// Тап по дню открывает его в виде «День». Свайп влево/вправо листает месяцы — страница едет за пальцем
/// (соседние месяцы отрисованы рядом). Каждая клетка — зона сброса (задача переезжает на этот день).
struct MonthView: View {
    /// Любой день нужного месяца.
    let anchor: Date
    let tasks: [PlannerTask]
    let drag: DragState?
    let onSelectDay: (Int) -> Void
    /// Пользователь пролистнул: +1 — следующий месяц, −1 — прошлый. Без анимации снаружи: она уже прошла.
    let onShiftMonth: (Int) -> Void

    @State private var dragX: CGFloat = 0
    @State private var axis: Axis?
    @State private var pageWidth: CGFloat = 0

    private var monthStart: Date { DayMath.monthStart(of: anchor) }

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
                let width = geometry.size.width
                HStack(spacing: 0) {
                    monthGrid(DayMath.date(monthStart, addingMonths: -1), byDay: byDay, size: geometry.size, live: false)
                    monthGrid(monthStart, byDay: byDay, size: geometry.size, live: true)
                    monthGrid(DayMath.date(monthStart, addingMonths: 1), byDay: byDay, size: geometry.size, live: false)
                }
                .offset(x: -width + dragX)
                .onChange(of: width, initial: true) { _, value in pageWidth = value }
            }
            .clipped()
        }
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .simultaneousGesture(swipe)
        .onChange(of: drag?.taskID) { _, id in
            // Взяли задачу — страницу не двигаем, даже если свайп уже начался.
            guard id != nil else { return }
            axis = .vertical
            if dragX != 0 { withAnimation(.easeOut(duration: 0.15)) { dragX = 0 } }
        }
        .task { await hintSwipeOnce() }
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

    // MARK: - Свайп

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                if axis == nil {
                    // Пока задачу держат над месяцем, страницу не двигаем.
                    axis = drag == nil && abs(value.translation.width) > abs(value.translation.height) * 1.3 ? .horizontal : .vertical
                }
                guard axis == .horizontal else { return }
                dragX = value.translation.width
            }
            .onEnded { value in
                let wasHorizontal = axis == .horizontal
                axis = nil
                guard wasHorizontal, pageWidth > 0 else { return }
                let width = pageWidth
                let projected = value.predictedEndTranslation.width
                if abs(value.translation.width) > width * 0.2 || abs(projected) > width * 0.45 {
                    let direction = value.translation.width < 0 ? 1 : -1
                    withAnimation(.easeOut(duration: 0.22)) {
                        dragX = -CGFloat(direction) * width
                    } completion: {
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            onShiftMonth(direction)
                            dragX = 0
                        }
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.2)) { dragX = 0 }
                }
            }
    }

    /// Один раз за запуск сетка чуть отъезжает и возвращается — видно, что сбоку есть следующий месяц.
    private func hintSwipeOnce() async {
        guard !MonthSwipeHint.shown else { return }
        MonthSwipeHint.shown = true
        try? await Task.sleep(for: .seconds(0.5))
        guard dragX == 0, drag == nil else { return }
        withAnimation(.easeInOut(duration: 0.28)) { dragX = -36 }
        try? await Task.sleep(for: .seconds(0.32))
        withAnimation(.spring(duration: 0.4, bounce: 0.3)) { dragX = 0 }
    }

    // MARK: - Сетка месяца

    /// Недели месяца как смещения дней от сегодняшнего: всегда шесть строк, чтобы сетка не прыгала.
    private func weeks(of start: Date) -> [[Int]] {
        let first = DayMath.offset(of: start)
        let gridStart = DayMath.weekStartOffset(containing: first)
        return (0..<6).map { row in (0..<7).map { gridStart + row * 7 + $0 } }
    }

    private func monthGrid(_ start: Date, byDay: [Date: [PlannerTask]], size: CGSize, live: Bool) -> some View {
        let rows = weeks(of: start)
        let monthIndex = DayMath.monthIndex(start)
        let cellHeight = size.height / CGFloat(max(1, rows.count))
        return VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(week, id: \.self) { offset in
                        cell(offset: offset, height: cellHeight, tasks: byDay[DayMath.day(offset: offset)] ?? [], monthIndex: monthIndex, live: live)
                    }
                }
                .frame(height: cellHeight)
                .overlay(alignment: .bottom) { Rectangle().fill(Tokens.line).frame(height: 1) }
            }
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(!live)
    }

    private func cell(offset: Int, height: CGFloat, tasks: [PlannerTask], monthIndex: Int, live: Bool) -> some View {
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
        .reportZone("tab-\(offset)", enabled: live)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DayMath.accessibilityLabel(offset: offset) + ", задач: \(tasks.count)")
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
            .opacity(task.isDone ? 0.5 : 1)
    }
}

/// Намёк на свайп показывается один раз за запуск.
@MainActor
enum MonthSwipeHint {
    static var shown = false
}
