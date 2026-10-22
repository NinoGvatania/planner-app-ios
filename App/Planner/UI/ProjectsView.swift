import PlannerCore
import SwiftData
import SwiftUI

/// Вид «Проекты»: секция на каждый проект (и «Без проекта»), секции сворачиваются.
/// Удержание задачи показывает поверх доску со всеми проектами — бросить можно в любой, не прокручивая.
struct ProjectsView: View {
    let tasks: [PlannerTask]
    let drag: DragState?
    let onToggle: (PlannerTask) -> Void
    let onDragChanged: (PlannerTask, CGPoint, CGPoint) -> Void
    let onDragEnded: () -> Void
    let onEdit: (PlannerTask) -> Void
    let onManageProjects: () -> Void
    var onDragCancelled: (() -> Void)? = nil
    /// Средняя страница пейджера: только она сообщает зоны сброса.
    var live = true

    @Query(sort: \Project.name) private var projects: [Project]
    @State private var collapsed: Set<String> = []

    private struct ProjectSection: Identifiable {
        let name: String?
        let style: QuadrantStyle
        var id: String { name ?? "" }
    }

    /// Секции: проекты по алфавиту, потом «Без проекта».
    private var sections: [ProjectSection] {
        projects.map { ProjectSection(name: $0.name, style: $0.style) } + [ProjectSection(name: nil, style: .unsorted)]
    }

    /// Задачи проекта за период из календаря (бэклога здесь нет): открытые выше, дальше по дате и времени.
    private func items(in name: String?) -> [PlannerTask] {
        tasks
            .filter { !$0.isRoutine && $0.project?.name == name }
            .sorted { a, b in
                if a.isDone != b.isDone { return !a.isDone }
                let da = a.day ?? .distantFuture, db = b.day ?? .distantFuture
                if da != db { return da < db }
                return (a.start ?? -1) < (b.start ?? -1)
            }
    }

    var body: some View {
        ZStack {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    ForEach(sections) { section in
                        self.section(name: section.name, style: section.style)
                    }
                    Button(action: onManageProjects) {
                        Label(projects.isEmpty ? "Создать проект" : "Проекты: добавить, переименовать, цвета…", systemImage: "folder.badge.plus")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Tokens.caption)
                            .frame(maxWidth: .infinity, minHeight: Tokens.hitTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.pageTap)
                }
                .padding(.horizontal, 10)
                .padding(.top, 4)
                .padding(.bottom, 16)
            }
            if drag != nil {
                dropBoard
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: drag != nil)
    }

    // MARK: - Секция проекта

    private func key(_ name: String?) -> String { name ?? "" }

    private func section(name: String?, style: QuadrantStyle) -> some View {
        let list = items(in: name)
        let isCollapsed = collapsed.contains(key(name))
        let open = list.filter { !$0.isDone }.count
        return VStack(spacing: 2) {
            Button {
                withAnimation(.spring(duration: 0.28)) {
                    if isCollapsed { collapsed.remove(key(name)) } else { collapsed.insert(key(name)) }
                }
            } label: {
                HStack(spacing: 8) {
                    Circle().fill(style.dot).frame(width: 10, height: 10)
                    Text(name ?? "Без проекта")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(name == nil ? Tokens.caption : Tokens.text)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text(open == list.count ? "\(list.count)" : "\(open) из \(list.count)")
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(style.dot)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Tokens.caption)
                        .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                }
                .padding(.horizontal, 12)
                .frame(height: Tokens.hitTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pageTap)
            .accessibilityLabel((isCollapsed ? "Развернуть: " : "Свернуть: ") + (name ?? "Без проекта"))
            if !isCollapsed {
                ForEach(list, id: \.id) { task in
                    row(task)
                }
                if list.isEmpty {
                    Text("Пусто — перетащи сюда задачу, удерживая её")
                        .font(.system(size: 13))
                        .foregroundStyle(Tokens.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                }
                Spacer(minLength: 6)
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .top)
        // При сворачивании гаснущие строки не вылезают из секции на соседнюю.
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .background(style.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(style.border, lineWidth: 1.5))
    }

    private func row(_ task: PlannerTask) -> some View {
        let today = DayMath.today()
        let overdue = task.isOverdue(today: today)
        return HStack(spacing: 2) {
            Button { onToggle(task) } label: {
                ZStack {
                    Circle()
                        .strokeBorder(task.style.dot, lineWidth: 2)
                        .frame(width: 20, height: 20)
                    if task.isDone {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(task.style.dot)
                    }
                }
                .frame(width: Tokens.hitTarget, height: Tokens.hitTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pageTap)
            .accessibilityLabel((task.isDone ? "Вернуть в работу: " : "Отметить выполненной: ") + task.title)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.system(size: 15))
                    .strikethrough(task.isDone)
                    .foregroundStyle(task.isDone ? Tokens.caption : Tokens.text)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(meta(task))
                    if let quadrant = task.sortedQuadrant {
                        Circle().fill(quadrant.style.dot).frame(width: 6, height: 6)
                        Text(quadrant.name.lowercased())
                    }
                }
                .font(.system(size: 12))
                .foregroundStyle(overdue ? Tokens.overdue : Tokens.caption)
                .lineLimit(1)
            }
            .padding(.vertical, 6)
            Spacer(minLength: 0)
        }
        .padding(.trailing, 8)
        .frame(minHeight: 50)
        .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 12))
        .opacity(drag?.taskID == task.id ? 0.35 : (task.isDone ? 0.6 : 1))
        .contentShape(Rectangle())
        .onPageTap { onEdit(task) }
        .gesture(HoldDragGesture(onChanged: { location, start in onDragChanged(task, location, start) }, onEnded: onDragEnded, onCancelled: onDragCancelled ?? onDragEnded))
    }

    private func meta(_ task: PlannerTask) -> String {
        if let day = task.day {
            let label = DayMath.label(offset: DayMath.offset(of: day))
            return task.start.map { label + " " + ClockGrid.format(minutes: $0) } ?? label
        }
        return "бэклог"
    }

    // MARK: - Доска для сброса

    /// Все проекты и «Без проекта» на одном экране, по два в ряд.
    private var dropBoard: some View {
        GeometryReader { geometry in
            let all = sections
            let rows = max(1, (all.count + 1) / 2)
            let spacing: CGFloat = 10
            let rowHeight = max(56, (geometry.size.height - 24 - spacing * CGFloat(rows)) / CGFloat(rows))
            VStack(spacing: spacing) {
                Text("В какой проект?")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Tokens.caption)
                    .frame(height: 24)
                ForEach(0..<rows, id: \.self) { row in
                    HStack(spacing: spacing) {
                        ForEach(0..<2, id: \.self) { column in
                            let index = row * 2 + column
                            if index < all.count {
                                boardTarget(name: all[index].name, style: all[index].style)
                            } else {
                                Color.clear
                            }
                        }
                    }
                    .frame(height: rowHeight)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
        }
        .padding(.bottom, 10)
        .background(Tokens.background.opacity(0.94))
        .allowsHitTesting(false)
    }

    private func boardTarget(name: String?, style: QuadrantStyle) -> some View {
        let hovered = drag?.target == .project(name)
        let count = items(in: name).filter { !$0.isDone }.count
        return VStack(spacing: 4) {
            Circle().fill(style.dot).frame(width: 12, height: 12)
            Text(name ?? "Без проекта")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(name == nil ? Tokens.caption : Tokens.text)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Text("\(count)")
                .font(.system(size: 12))
                .foregroundStyle(Tokens.caption)
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Фон ровно по форме рамки (стекло рисовало подложку шире рамки).
        .background(hovered ? Tokens.accent.opacity(0.22) : style.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(hovered ? Tokens.accent : style.border, lineWidth: hovered ? 2.5 : 1.5))
        .scaleEffect(hovered ? 1.02 : 1)
        .animation(.easeOut(duration: 0.12), value: hovered)
        .reportZone("project-" + (name ?? ""), enabled: live && drag != nil)
    }
}
