import Foundation
import PlannerCore
import SwiftData
import SwiftUI

/// Единственный экран приложения: шапка, рабочая поверхность, панель бэклога.
struct PlannerScreen: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PlannerTask.createdAt) private var tasks: [PlannerTask]

    @State private var dayOffset = 0
    @State private var mode: ViewMode = .day
    @State private var showDone = true
    @State private var drawerOpen = false
    @State private var showOverdue = false
    @State private var input = ""
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?
    @State private var selectedID: UUID?
    @State private var drag: DragState?
    @State private var zones: [String: CGRect] = [:]
    @State private var springTask: Task<Void, Never>?
    @State private var springOffset: Int?
    @State private var namingTask: PlannerTask?
    @State private var newTitle = ""

    private let gridTopInset: CGFloat = 10

    private var today: Date { DayMath.today() }
    private var visibleTasks: [PlannerTask] { showDone ? tasks : tasks.filter { !$0.isDone } }
    private var overdueTasks: [PlannerTask] {
        tasks.filter { $0.isOverdue(today: today) }
            .sorted { ($0.day ?? today, $0.start ?? 0) < ($1.day ?? today, $1.start ?? 0) }
    }
    private var backlogTasks: [PlannerTask] {
        tasks.filter { $0.isInBacklog && (!$0.isDone || showDone) }
            .sorted { a, b in
                if a.isDone != b.isDone { return !a.isDone }
                return a.backlogRank > b.backlogRank
            }
    }
    private var dayTasks: [PlannerTask] {
        let date = DayMath.day(offset: dayOffset)
        return visibleTasks.filter { $0.day == date }
    }
    private var hoveredTab: Int? {
        if case .dayTab(let offset) = drag?.target { return offset }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(
                title: mode == .day ? DayMath.title(offset: dayOffset) : mode.title,
                subtitle: mode == .day ? DayMath.subtitle(offset: dayOffset) : "Скоро",
                overdueCount: overdueTasks.count,
                todayNumber: DayMath.dayOfMonth(today),
                mode: $mode,
                showDone: $showDone,
                onOverdue: { showOverdue = true },
                onToday: { withAnimation { dayOffset = 0 } }
            )

            if mode == .day {
                WeekStripView(dayOffset: $dayOffset, hasTasks: { offset in
                    let date = DayMath.day(offset: offset)
                    return visibleTasks.contains { $0.day == date }
                }, hoveredOffset: hoveredTab)
                DayTimelineView(
                    timed: dayTasks.filter { $0.start != nil },
                    allDay: dayTasks.filter { $0.start == nil },
                    showNow: dayOffset == 0,
                    selectedID: $selectedID,
                    drag: drag,
                    onToggle: toggleDone,
                    onResize: resize,
                    onDragChanged: dragChanged,
                    onDragEnded: dragEnded,
                    onCreate: createTask
                )
                .id(dayOffset)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: mode.symbol)
                        .font(.system(size: 40))
                        .foregroundStyle(Tokens.muted)
                    Text("Вид «\(mode.title)» появится на этапе 2")
                        .font(.system(size: 15))
                        .foregroundStyle(Tokens.caption)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            BacklogDrawerView(
                tasks: backlogTasks,
                isOpen: $drawerOpen,
                input: $input,
                onSubmit: submitInput,
                onVoice: { showToast("Голосовой ввод появится на этапе 2") },
                onToggle: toggleDone,
                drag: drag,
                onDragChanged: dragChanged,
                onDragEnded: dragEnded
            )
        }
        .coordinateSpace(name: "planner")
        .onPreferenceChange(ZoneFramesKey.self) { zones = $0 }
        .background(Tokens.background.ignoresSafeArea())
        .foregroundStyle(Tokens.text)
        .overlay(alignment: .bottom) { toastView }
        .overlay(alignment: .topLeading) { ghostView }
        .animation(.easeOut(duration: 0.22), value: toast)
        .sheet(isPresented: $showOverdue) {
            OverdueSheet(
                tasks: overdueTasks,
                onToggle: toggleDone,
                onFitToday: { fitOverdue(dayOffset: 0) },
                onFitTomorrow: { fitOverdue(dayOffset: 1) },
                onToBacklog: overdueToBacklog
            )
        }
        .task {
            SeedData.seedIfNeeded(in: context)
            NotificationScheduler.requestPermission()
            NotificationScheduler.sync(tasks)
        }
        .onChange(of: mode) { _, _ in selectedID = nil }
        .alert("Новая задача", isPresented: Binding(get: { namingTask != nil }, set: { if !$0 { namingTask = nil } }), presenting: namingTask) { task in
            TextField("Название", text: $newTitle)
            Button("Готово") { finishNaming(task, keep: true) }
            Button("Отмена", role: .cancel) { finishNaming(task, keep: false) }
        } message: { task in
            Text(whenText(task))
        }
    }

    /// Тап или протягивание по свободному месту сетки: задача создаётся сразу, название спрашивается следом.
    private func createTask(start: Int, duration: Int) {
        let task = PlannerTask(
            title: "Новая задача",
            day: DayMath.day(offset: dayOffset),
            start: start,
            duration: duration,
            backlogRank: (tasks.map { $0.backlogRank }.max() ?? 0) + 1
        )
        context.insert(task)
        selectedID = task.id
        newTitle = ""
        namingTask = task
    }

    private func finishNaming(_ task: PlannerTask, keep: Bool) {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if keep {
            if !title.isEmpty { task.title = title.capitalizedFirst }
            NotificationScheduler.sync(tasks)
        } else {
            if selectedID == task.id { selectedID = nil }
            context.delete(task)
        }
        namingTask = nil
        newTitle = ""
    }

    // MARK: - Оверлеи

    @ViewBuilder
    private var toastView: some View {
        if let toast = toast {
            Text(toast)
                .font(.system(size: 14))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Tokens.badge, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                .shadow(color: Color.black.opacity(0.4), radius: 12, y: 8)
                .padding(.horizontal, 16)
                .padding(.bottom, Tokens.drawerCollapsed + 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private var ghostView: some View {
        if let drag = drag {
            VStack(alignment: .leading, spacing: 2) {
                Text(drag.title)
                    .font(.system(size: 14, weight: .semibold))
                    .lineLimit(1)
                Text(ghostMeta(drag))
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(drag.target == nil ? Tokens.caption : Tokens.accent)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(width: 210, alignment: .leading)
            .background(Tokens.badge, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(drag.target == nil ? Color(hex: 0x4A4B52) : Tokens.accent, lineWidth: 1.5))
            .shadow(color: Color.black.opacity(0.55), radius: 17, y: 16)
            .rotationEffect(.degrees(-2))
            .position(x: drag.location.x + 60, y: drag.location.y - 46)
            .allowsHitTesting(false)
        }
    }

    private func ghostMeta(_ drag: DragState) -> String {
        switch drag.target {
        case .grid(let start):
            return ClockGrid.format(minutes: start) + "–" + ClockGrid.format(minutes: start + drag.duration)
        case .allDay:
            return DayMath.label(offset: dayOffset).capitalizedFirst + " · весь день"
        case .dayTab(let offset):
            return offset == dayOffset ? "На " + DayMath.label(offset: offset) : "Подержи — открою " + DayMath.label(offset: offset)
        case .backlog:
            return "В бэклог"
        case nil:
            return "Тащи на нужное время"
        }
    }

    // MARK: - Перетаскивание

    private func dragChanged(_ task: PlannerTask, location: CGPoint, startLocation: CGPoint) {
        if drag == nil || drag?.taskID != task.id {
            var grab: CGFloat = min(CGFloat(task.duration) / 60 * Tokens.hourHeight / 2, 20)
            let fromTimeline = task.day != nil && task.start != nil
            if fromTimeline, let grid = zones["grid"], let start = task.start,
               task.day == DayMath.day(offset: dayOffset) {
                let blockTop = grid.minY + gridTopInset + CGFloat(start) / 60 * Tokens.hourHeight
                grab = max(0, startLocation.y - blockTop)
            }
            drag = DragState(taskID: task.id, title: task.title, duration: task.duration, location: location,
                             grabOffsetY: grab, fromTimeline: task.day != nil, target: nil)
            selectedID = nil
            if drawerOpen && task.isInBacklog { drawerOpen = false }
        }
        drag?.location = location
        let target = dropTarget(at: location, duration: task.duration, grab: drag?.grabOffsetY ?? 0)
        drag?.target = target
        updateSpring(for: target)
    }

    private func dragEnded() {
        guard let state = drag else { return }
        drag = nil
        springTask?.cancel()
        springOffset = nil
        guard let target = state.target, let task = tasks.first(where: { $0.id == state.taskID }) else { return }
        switch target {
        case .backlog:
            guard !task.isInBacklog else { return }
            task.day = nil
            task.start = nil
            task.backlogRank = (tasks.map { $0.backlogRank }.max() ?? 0) + 1
            showToast("Вернул в бэклог: «\(task.title)»")
        case .grid(let start):
            task.day = DayMath.day(offset: dayOffset)
            task.start = start
            selectedID = task.id
        case .allDay:
            task.day = DayMath.day(offset: dayOffset)
            task.start = nil
        case .dayTab(let offset):
            task.day = DayMath.day(offset: offset)
            showToast("«\(task.title)» — " + whenText(task))
        }
        NotificationScheduler.sync(tasks)
    }

    private func dropTarget(at point: CGPoint, duration: Int, grab: CGFloat) -> DropTarget? {
        if let drawer = zones["drawer"], drawer.contains(point) { return .backlog }
        for offset in 0..<7 {
            if let tab = zones["tab-\(offset)"], tab.contains(point) { return .dayTab(offset: offset) }
        }
        if let allDay = zones["allday"], allDay.contains(point) { return .allDay }
        if let grid = zones["grid"], grid.contains(point) {
            let y = point.y - grab - grid.minY - gridTopInset
            let minutes = Int((y / Tokens.hourHeight * 60 / 15).rounded()) * 15
            return .grid(start: ClockGrid.clampedStart(minutes, duration: duration))
        }
        return nil
    }

    /// Задержка над вкладкой дня ~0,4 с открывает этот день.
    private func updateSpring(for target: DropTarget?) {
        guard case .dayTab(let offset) = target, offset != dayOffset else {
            springTask?.cancel()
            springOffset = nil
            return
        }
        guard springOffset != offset else { return }
        springOffset = offset
        springTask?.cancel()
        springTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.4))
            if !Task.isCancelled, drag != nil {
                withAnimation { dayOffset = offset }
            }
        }
    }

    // MARK: - Действия

    private func toggleDone(_ task: PlannerTask) {
        task.isDone.toggle()
        task.completedAt = task.isDone ? Date() : nil
        if task.isDone, task.isInBacklog {
            showToast("Готово: «\(task.title)»")
        }
        NotificationScheduler.sync(tasks)
    }

    private func resize(_ task: PlannerTask, to duration: Int) {
        task.duration = duration
        NotificationScheduler.sync(tasks)
    }

    private func fitOverdue(dayOffset target: Int) {
        let overdue = overdueTasks
        guard !overdue.isEmpty else { showOverdue = false; return }
        let day = DayMath.day(offset: target)
        let overdueIDs = Set(overdue.map { $0.id })
        let busy = tasks
            .filter { task in task.day == day && task.start != nil && !overdueIDs.contains(task.id) }
            .map { BusyInterval(start: $0.start ?? 0, end: ($0.start ?? 0) + $0.duration) }
        let candidates = overdue.map {
            SchedulingCandidate(id: $0.id.uuidString, duration: $0.duration, quadrant: $0.quadrant,
                                order: $0.day.map { DayMath.offset(of: $0) } ?? 0)
        }
        let from = target == 0 ? DayMath.nowMinutes() : 9 * 60
        let placements = FreeSlotScheduler.fit(candidates, busy: busy, from: from)
        var placed: [Int] = []
        var left = 0
        for placement in placements {
            guard let task = overdue.first(where: { $0.id.uuidString == placement.id }) else { continue }
            if let start = placement.start {
                task.day = day
                task.start = start
                placed.append(start)
            } else {
                task.day = nil
                task.start = nil
                task.backlogRank = (tasks.map { $0.backlogRank }.max() ?? 0) + 1
                left += 1
            }
        }
        showOverdue = false
        mode = .day
        dayOffset = target
        selectedID = nil
        let times = placed.sorted().map { ClockGrid.format(minutes: $0) }.joined(separator: ", ")
        var message = placed.isEmpty ? "Свободных окон нет" : (target == 0 ? "Разложил на сегодня: " : "Перенёс на завтра: ") + times
        if left > 0 { message += " · не влезло \(left) — в бэклоге" }
        showToast(message)
        NotificationScheduler.sync(tasks)
    }

    private func overdueToBacklog() {
        let overdue = overdueTasks
        var rank = tasks.map { $0.backlogRank }.max() ?? 0
        for task in overdue {
            rank += 1
            task.day = nil
            task.start = nil
            task.backlogRank = rank
        }
        showOverdue = false
        if !overdue.isEmpty { drawerOpen = true }
        let n = overdue.count
        showToast(n == 0 ? "Просроченных задач нет" : "Убрал в бэклог: \(n) " + DayMath.plural(n, "задачу", "задачи", "задач"))
        NotificationScheduler.sync(tasks)
    }

    private func submitInput() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        input = ""
        let parser = QuickAddParser()
        switch parser.parse(text) {
        case .task(let parsed):
            addTask(parsed)
        case .agenda(let offset):
            let date = DayMath.day(offset: offset)
            let items = tasks
                .filter { $0.day == date && !$0.isDone }
                .sorted { ($0.start ?? -1) < ($1.start ?? -1) }
            let summary = items.isEmpty
                ? "ничего не запланировано"
                : items.map { ($0.start.map { ClockGrid.format(minutes: $0) + " " } ?? "") + $0.title }.joined(separator: "; ")
            showToast(DayMath.label(offset: offset).capitalizedFirst + ": " + summary)
        case .fitOverdue(let offset):
            fitOverdue(dayOffset: offset)
        }
    }

    private func addTask(_ parsed: ParsedTask) {
        let project = parsed.project.map { findOrCreateProject(named: $0) }
        let rank = (tasks.map { $0.backlogRank }.max() ?? 0) + 1
        let task = PlannerTask(
            title: parsed.title,
            day: parsed.dayOffset.map { DayMath.day(offset: $0) },
            start: parsed.start,
            duration: parsed.duration,
            quadrant: parsed.quadrant,
            project: project,
            backlogRank: rank
        )
        context.insert(task)
        if let offset = parsed.dayOffset, mode == .day, (0...6).contains(offset) {
            dayOffset = offset
        }
        if parsed.start != nil { selectedID = task.id }
        let quadrantNote = parsed.quadrant == .other ? "" : " · " + parsed.quadrant.name.lowercased()
        showToast("«\(parsed.title)» — \(whenText(task))\(quadrantNote)")
        NotificationScheduler.sync(tasks + [task])
    }

    private func whenText(_ task: PlannerTask) -> String {
        guard let day = task.day else { return "в бэклог" }
        let label = DayMath.label(offset: DayMath.offset(of: day))
        guard let start = task.start else { return label + " · весь день" }
        return label + " · " + ClockGrid.format(minutes: start) + "–" + ClockGrid.format(minutes: start + task.duration)
    }

    private func findOrCreateProject(named name: String) -> Project {
        let descriptor = FetchDescriptor<Project>(predicate: #Predicate<Project> { $0.name == name })
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let project = Project(name: name)
        context.insert(project)
        return project
    }

    private func showToast(_ message: String) {
        toastTask?.cancel()
        toast = message
        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.8))
            if !Task.isCancelled {
                toast = nil
            }
        }
    }
}

extension String {
    var capitalizedFirst: String {
        guard let first = first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}
