import PlannerCore
import SwiftUI

/// Матрица Эйзенхауэра: четыре квадранта, каждый — зона сброса; перетаскивание меняет квадрант задачи.
struct MatrixView: View {
    let tasks: [PlannerTask]
    let drag: DragState?
    let onToggle: (PlannerTask) -> Void
    let onDragChanged: (PlannerTask, CGPoint, CGPoint) -> Void
    let onDragEnded: () -> Void
    let onEdit: (PlannerTask) -> Void

    private let labelWidth: CGFloat = 18

    private func items(for quadrant: Quadrant) -> [PlannerTask] {
        let today = DayMath.today()
        func rank(_ task: PlannerTask) -> Int {
            guard let day = task.day else { return 2 }
            return day < today ? 0 : 1
        }
        return tasks
            .filter { !$0.isDone && !$0.isRoutine && $0.quadrantRaw == quadrant.rawValue }
            .sorted { a, b in
                let ra = rank(a), rb = rank(b)
                if ra != rb { return ra < rb }
                if ra == 2 { return a.backlogRank > b.backlogRank }
                let da = a.day ?? today, db = b.day ?? today
                if da != db { return da < db }
                return (a.start ?? -1) < (b.start ?? -1)
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Color.clear.frame(width: labelWidth)
                axisLabel("Срочно")
                axisLabel("Не срочно")
            }
            .frame(height: 22)
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    rowLabel("Важно")
                    cell(.urgentImportant)
                    cell(.important)
                }
                GridRow {
                    rowLabel("Не важно")
                    cell(.urgent)
                    cell(.other)
                }
            }
            .frame(maxHeight: .infinity)
            unsortedTray
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    private var unsortedTasks: [PlannerTask] {
        tasks
            .filter { !$0.isDone && !$0.isRoutine && !$0.isSorted }
            .sorted { a, b in
                if (a.day == nil) != (b.day == nil) { return a.day != nil }
                if let da = a.day, let db = b.day, da != db { return da < db }
                return a.backlogRank > b.backlogRank
            }
    }

    /// Неразобранные задачи: серые, ждут, когда их перетащат в квадрант. Сюда же можно вернуть задачу.
    private var unsortedTray: some View {
        let list = unsortedTasks
        let hovered = drag?.target == .quadrant(0)
        let style = QuadrantStyle.unsorted
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Circle().fill(style.dot).frame(width: 10, height: 10)
                Text("Не разобрано")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(Tokens.caption)
                Spacer(minLength: 0)
                Text("\(list.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Tokens.muted)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(list, id: \.id) { task in
                        trayChip(task)
                    }
                    if list.isEmpty {
                        Text("Всё разобрано")
                            .font(.system(size: 12.5))
                            .foregroundStyle(Tokens.muted)
                            .padding(.horizontal, 4)
                            .frame(height: 44)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 6)
            }
        }
        .frame(height: 92)
        .background(hovered ? Tokens.accent.opacity(0.12) : style.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(hovered ? Tokens.accent : style.border, lineWidth: 1.5))
        .padding(.leading, labelWidth + 8)
        .padding(.top, 8)
        .reportZone("quad-0")
    }

    private func trayChip(_ task: PlannerTask) -> some View {
        Text(task.title)
            .font(.system(size: 13))
            .lineLimit(1)
            .foregroundStyle(Tokens.text)
            .padding(.horizontal, 12)
            .frame(height: Tokens.hitTarget)
            .frame(maxWidth: 200)
            .background(Color.black.opacity(0.25), in: Capsule())
            .opacity(drag?.taskID == task.id ? 0.35 : 1)
            .contentShape(Capsule())
            .onTapGesture { onEdit(task) }
            .gesture(
                LongPressGesture(minimumDuration: 0.3)
                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("planner")))
                    .onChanged { value in
                        if case .second(true, let dragValue?) = value {
                            onDragChanged(task, dragValue.location, dragValue.startLocation)
                        }
                    }
                    .onEnded { _ in onDragEnded() }
            )
    }

    private func axisLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .kerning(0.6)
            .foregroundStyle(Tokens.caption)
            .frame(maxWidth: .infinity)
    }

    private func rowLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .kerning(0.6)
            .foregroundStyle(Tokens.caption)
            .fixedSize()
            .rotationEffect(.degrees(-90))
            .frame(width: labelWidth)
            .frame(maxHeight: .infinity)
    }

    private func cell(_ quadrant: Quadrant) -> some View {
        let style = quadrant.style
        let list = items(for: quadrant)
        let hovered = drag?.target == .quadrant(quadrant.rawValue)
        return VStack(spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(style.dot).frame(width: 10, height: 10)
                Text(quadrant.label)
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(style.text)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(list.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(style.dot)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 3) {
                    ForEach(list, id: \.id) { task in
                        row(task, style: style)
                    }
                    if list.isEmpty {
                        Text("Пусто — перетащи сюда")
                            .font(.system(size: 12.5))
                            .foregroundStyle(style.text.opacity(0.75))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6)
                    }
                }
                .padding(.horizontal, 5)
                .padding(.bottom, 5)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(hovered ? Tokens.accent.opacity(0.12) : style.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(hovered ? Tokens.accent : style.border, lineWidth: 1.5))
        .reportZone("quad-\(quadrant.rawValue)")
        .accessibilityLabel(quadrant.name)
    }

    private func row(_ task: PlannerTask, style: QuadrantStyle) -> some View {
        let today = DayMath.today()
        let overdue = task.isOverdue(today: today)
        let meta: String
        if let day = task.day {
            let label = DayMath.label(offset: DayMath.offset(of: day))
            meta = task.start.map { label + " " + ClockGrid.format(minutes: $0) } ?? label
        } else {
            meta = "бэклог"
        }
        return HStack(spacing: 0) {
            Button { onToggle(task) } label: {
                Circle()
                    .strokeBorder(task.style.dot, lineWidth: 2)
                    .frame(width: 16, height: 16)
                    .frame(width: 34)
                    .frame(maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Отметить выполненной: " + task.title)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.system(size: 12.5))
                    .foregroundStyle(style.text)
                    .lineLimit(2)
                Text(meta)
                    .font(.system(size: 11))
                    .foregroundStyle(overdue ? Tokens.overdue : Tokens.caption)
                    .lineLimit(1)
            }
            .padding(.vertical, 5)
            Spacer(minLength: 0)
        }
        .padding(.trailing, 6)
        .frame(minHeight: 46)
        .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 10))
        .opacity(drag?.taskID == task.id ? 0.35 : 1)
        .contentShape(Rectangle())
        .onTapGesture { onEdit(task) }
        .gesture(
            LongPressGesture(minimumDuration: 0.3)
                .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("planner")))
                .onChanged { value in
                    if case .second(true, let dragValue?) = value {
                        onDragChanged(task, dragValue.location, dragValue.startLocation)
                    }
                }
                .onEnded { _ in onDragEnded() }
        )
    }
}
