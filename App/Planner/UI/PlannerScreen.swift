import Foundation
import PlannerCore
import SwiftData
import SwiftUI

/// Единственный экран приложения: шапка, рабочая поверхность, панель бэклога.
struct PlannerScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \PlannerTask.createdAt) private var tasks: [PlannerTask]

    @State private var dayOffset = 0
    @State private var mode: ViewMode = .day
    @State private var showDone = true
    @State private var drawerOpen = false
    @State private var showOverdue = false
    @State private var showVoice = false
    @State private var input = ""
    @State private var toast: ToastMessage?
    @State private var toastTask: Task<Void, Never>?
    @State private var toastAction: (() -> Void)?
    @State private var selectedID: UUID?
    @State private var drag: DragState?
    @State private var zones: [String: CGRect] = [:]
    @State private var springTask: Task<Void, Never>?
    @State private var springOffset: Int?
    @State private var namingTask: PlannerTask?
    @State private var editingTask: PlannerTask?
    @State private var newTitle = ""
    @State private var rootSize: CGSize = .zero
    @State private var gridScroll = GridScroll()
    @State private var scrollToNowRequest = 0
    @State private var showProjects = false
    @State private var showSettings = false
    @State private var showStreak = false
    /// Откуда пришли в текущий вид (месяц → день, неделя → день): кнопка «назад» ведёт обратно.
    @State private var navStack: [ViewMode] = []
    /// Горизонтальный сдвиг сетки дня при свайпе между днями.
    @State private var pageX: CGFloat = 0
    @State private var swipeAxis: Axis?
    @AppStorage("colorMode") private var colorModeRaw = ColorMode.quadrant.rawValue

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
    /// Понедельник недели выбранного дня.
    private var weekStart: Int { DayMath.weekStartOffset(containing: dayOffset) }
    /// Дни, показанные на сетке: один в режиме «День», неделя с понедельника в режиме «Неделя».
    private var visibleDays: [Int] {
        mode == .week ? Array(weekStart...(weekStart + 6)) : [dayOffset]
    }
    /// Заголовок кнопки «назад»: название вида, из которого открыли текущий.
    private var backTitle: String? {
        guard let parent = navStack.last else { return nil }
        return parent == .month ? DayMath.monthNominative[DayMath.monthIndex(monthAnchor)] : parent.title
    }
    private var monthAnchor: Date { DayMath.day(offset: dayOffset) }

    private var headerTitle: String {
        switch mode {
        case .day: return DayMath.title(offset: dayOffset)
        case .week: return rangeTitle(from: weekStart, to: weekStart + 6)
        case .weekList: return rangeTitle(from: 0, to: 6)
        case .month: return DayMath.monthNominative[DayMath.monthIndex(monthAnchor)] + " \(DayMath.year(monthAnchor))"
        case .matrix: return "Матрица"
        case .projects: return "Проекты"
        case .dashboard: return "Дашборд"
        }
    }

    private var headerSubtitle: String {
        switch mode {
        case .day: return DayMath.subtitle(offset: dayOffset)
        case .week:
            let n = countTasks(from: weekStart, to: weekStart + 6)
            return "Неделя · \(n) " + DayMath.plural(n, "задача", "задачи", "задач")
        case .weekList: return "Неделя списком"
        case .month:
            let start = DayMath.offset(of: DayMath.monthStart(of: monthAnchor))
            let end = DayMath.offset(of: DayMath.date(DayMath.monthStart(of: monthAnchor), addingMonths: 1)) - 1
            let n = countTasks(from: start, to: end)
            return "\(n) " + DayMath.plural(n, "задача", "задачи", "задач") + " в месяце"
        case .matrix:
            let n = tasks.filter { !$0.isDone && !$0.isRoutine }.count
            return "\(n) " + DayMath.plural(n, "открытая задача", "открытые задачи", "открытых задач")
        case .projects:
            let n = tasks.filter { !$0.isDone && !$0.isRoutine && $0.project != nil }.count
            return "\(n) " + DayMath.plural(n, "задача", "задачи", "задач") + " в проектах"
        case .dashboard:
            return "Время по проектам"
        }
    }

    private func countTasks(from first: Int, to last: Int) -> Int {
        let a = DayMath.day(offset: first), b = DayMath.day(offset: last)
        return visibleTasks.filter { task in
            guard let day = task.day else { return false }
            return day >= a && day <= b
        }.count
    }

    /// «20–22 окт» или «30 окт – 1 ноя».
    private func rangeTitle(from first: Int, to last: Int) -> String {
        let d0 = DayMath.day(offset: first), d1 = DayMath.day(offset: last)
        return DayMath.monthIndex(d0) == DayMath.monthIndex(d1)
            ? "\(DayMath.dayOfMonth(d0))–\(DayMath.dayOfMonth(d1)) \(DayMath.monthShort[DayMath.monthIndex(d0)])"
            : "\(DayMath.dayOfMonth(d0)) \(DayMath.monthShort[DayMath.monthIndex(d0)]) – \(DayMath.dayOfMonth(d1)) \(DayMath.monthShort[DayMath.monthIndex(d1)])"
    }

    private var hoveredTab: Int? {
        if case .dayTab(let offset) = drag?.target { return offset }
        return nil
    }

    var body: some View {
        // Размер берётся у GeometryReader: он задаётся системой и не зависит от содержимого,
        // иначе панель бэклога «на весь экран» раздувала бы стек и сама же росла от него.
        GeometryReader { geometry in
            screen
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                .onChange(of: geometry.size, initial: true) { _, size in rootSize = size }
        }
    }

    private var screen: some View {
        VStack(spacing: 0) {
            HeaderView(
                title: headerTitle,
                subtitle: headerSubtitle,
                overdueCount: overdueTasks.count,
                todayNumber: DayMath.dayOfMonth(today),
                mode: Binding(
                    get: { mode },
                    set: { value in
                        navStack = []
                        withAnimation(.easeOut(duration: 0.2)) { mode = value }
                    }
                ),
                showDone: $showDone,
                colorMode: Binding(
                    get: { ColorMode(rawValue: colorModeRaw) ?? .quadrant },
                    set: { colorModeRaw = $0.rawValue }
                ),
                backTitle: backTitle,
                onBack: goBack,
                onOverdue: { showOverdue = true },
                onToday: {
                    withAnimation {
                        dayOffset = 0
                        if mode == .matrix || mode == .weekList || mode == .projects || mode == .dashboard {
                            mode = .day
                            navStack = []
                        }
                    }
                    scrollToNowRequest += 1
                },
                onProjects: { showProjects = true },
                onSettings: { showSettings = true }
            )

            switch mode {
            case .day, .week:
                if mode == .day {
                    WeekStripView(dayOffset: $dayOffset, start: weekStart, hasTasks: { offset in
                        let date = DayMath.day(offset: offset)
                        return visibleTasks.contains { $0.day == date }
                    }, hoveredOffset: hoveredTab, onShiftWeek: { direction in
                        slideDays(by: 7 * direction, direction: direction)
                    })
                }
                DayTimelineView(
                    days: visibleDays,
                    tasks: visibleTasks,
                    selectedID: $selectedID,
                    drag: drag,
                    onToggle: toggleDone,
                    onResize: resize,
                    onRetime: retime,
                    onDragChanged: dragChanged,
                    onDragEnded: dragEnded,
                    onCreate: createTask,
                    onEdit: { editingTask = $0 },
                    onShiftDays: shiftDays,
                    onSelectDay: { offset in
                        navStack = [.week]
                        withAnimation(.easeOut(duration: 0.2)) {
                            dayOffset = offset
                            mode = .day
                        }
                    },
                    scroll: gridScroll,
                    onAutoScrollTick: refreshDropTarget,
                    scrollToNowRequest: scrollToNowRequest,
                    onDragCancelled: dragCancelled
                )
                .offset(x: mode == .day ? pageX : 0)
                .clipped()
                .simultaneousGesture(daySwipe, including: mode == .day ? .all : .subviews)
            case .month:
                MonthView(
                    anchor: monthAnchor,
                    tasks: visibleTasks,
                    drag: drag,
                    onSelectDay: { offset in
                        navStack = [.month]
                        withAnimation(.easeOut(duration: 0.2)) {
                            dayOffset = offset
                            mode = .day
                        }
                    },
                    onShiftMonth: { delta in
                        // Страница уже уехала за пальцем — подменяем месяц без анимации.
                        dayOffset = DayMath.offset(of: DayMath.date(monthAnchor, addingMonths: delta))
                    }
                )
            case .matrix:
                MatrixView(tasks: tasks, drag: drag, onToggle: toggleDone, onDragChanged: dragChanged, onDragEnded: dragEnded, onEdit: { editingTask = $0 }, onDelete: deleteTask, onDragCancelled: dragCancelled)
            case .weekList:
                WeekListView(tasks: visibleTasks, drag: drag, onToggle: toggleDone, onDragChanged: dragChanged, onDragEnded: dragEnded, onEdit: { editingTask = $0 }, onDragCancelled: dragCancelled)
            case .projects:
                ProjectsView(tasks: visibleTasks, drag: drag, onToggle: toggleDone, onDragChanged: dragChanged, onDragEnded: dragEnded, onEdit: { editingTask = $0 }, onManageProjects: { showProjects = true }, onDragCancelled: dragCancelled)
            case .dashboard:
                DashboardView(tasks: tasks, onOpenProjects: { showProjects = true })
            }

            BacklogDrawerView(
                tasks: backlogTasks,
                isOpen: $drawerOpen,
                input: $input,
                onSubmit: submitInput,
                onVoice: { showVoice = true },
                onToggle: toggleDone,
                drag: drag,
                onDragChanged: dragChanged,
                onDragEnded: dragEnded,
                onEdit: { editingTask = $0 },
                onDelete: deleteTask,
                maxHeight: rootSize.height > 0 ? max(Tokens.drawerCollapsed + 100, rootSize.height - 62 - (mode == .day ? 64 : 0) - 24) : .infinity,
                onDragCancelled: dragCancelled,
                streak: streakInfo.current,
                onStreak: { showStreak = true }
            )
        }
        .coordinateSpace(name: "planner")
        .onPreferenceChange(ZoneFramesKey.self) { zones = $0 }
        .onChange(of: zones) { _, _ in refreshDropTarget() }
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
                onToBacklog: overdueToBacklog,
                onDelete: deleteTask,
                onChanged: { NotificationScheduler.sync(tasks) }
            )
        }
        .task {
            SeedData.seedIfNeeded(in: context)
            SeedData.assignProjectColorsIfNeeded(in: context)
            let created = RoutineManager.materialize(in: context)
            NotificationScheduler.requestPermission()
            NotificationScheduler.sync(tasks + created)
        }
        .onChange(of: scenePhase) { _, phase in
            // Вернулись в приложение (возможно, уже другой день): досоздать рутины, обновить напоминания.
            guard phase == .active else { return }
            let created = RoutineManager.materialize(in: context)
            NotificationScheduler.sync(tasks + created)
        }
        .onChange(of: mode) { _, _ in
            selectedID = nil
            drag = nil
            springTask?.cancel()
            springOffset = nil
            pageX = 0
            swipeAxis = nil
        }
        .fullScreenCover(isPresented: $showVoice) {
            VoiceInputSheet(onDone: addDrafts)
        }
        .sheet(isPresented: $showProjects) {
            ProjectsSheet()
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet()
        }
        .sheet(isPresented: $showStreak) {
            StreakSheet(info: streakInfo)
        }
        .sheet(item: $editingTask) { task in
            TaskEditSheet(
                task: task,
                onDelete: { deleteTask(task) },
                onChanged: { NotificationScheduler.sync(tasks) }
            )
        }
        .alert("Новая задача", isPresented: Binding(get: { namingTask != nil }, set: { if !$0 { namingTask = nil } }), presenting: namingTask) { task in
            TextField("Название", text: $newTitle)
            Button("Готово") { finishNaming(task, keep: true) }
            Button("Отмена", role: .cancel) { finishNaming(task, keep: false) }
        } message: { task in
            Text(whenText(task))
        }
    }

    /// Свайп по заголовкам недели: окно сдвигается на неделю.
    private func shiftDays(by delta: Int) {
        withAnimation(.easeOut(duration: 0.2)) {
            dayOffset = max(-365, min(365, dayOffset + delta))
        }
    }

    /// Кнопка «назад»: вернуться в вид, из которого открыли текущий.
    private func goBack() {
        guard let parent = navStack.popLast() else { return }
        withAnimation(.easeOut(duration: 0.2)) { mode = parent }
    }

    /// Свайп по сетке дня: влево — следующий день, вправо — прошлый. Сетка едет за пальцем;
    /// пока задачу держат, свайп не работает, а вертикальная прокрутка остаётся прокруткой.
    private var daySwipe: some Gesture {
        DragGesture(minimumDistance: 14, coordinateSpace: .named("planner"))
            .onChanged { value in
                if swipeAxis == nil {
                    swipeAxis = drag == nil && abs(value.translation.width) > abs(value.translation.height) * 1.4 ? .horizontal : .vertical
                }
                guard swipeAxis == .horizontal, drag == nil else { return }
                pageX = value.translation.width
            }
            .onEnded { value in
                let horizontal = swipeAxis == .horizontal
                swipeAxis = nil
                guard horizontal else { return }
                let width = rootSize.width
                guard drag == nil, width > 0 else {
                    withAnimation(.easeOut(duration: 0.2)) { pageX = 0 }
                    return
                }
                if abs(value.translation.width) > width * 0.22 || abs(value.predictedEndTranslation.width) > width * 0.5 {
                    let direction = value.translation.width < 0 ? 1 : -1
                    slideDays(by: direction, direction: direction)
                } else {
                    withAnimation(.easeOut(duration: 0.2)) { pageX = 0 }
                }
            }
    }

    /// Уехать в сторону `direction`, подменить день на `delta` и въехать с другой стороны.
    private func slideDays(by delta: Int, direction: Int) {
        let width = rootSize.width
        guard width > 0 else {
            shiftDays(by: delta)
            return
        }
        withAnimation(.easeOut(duration: 0.16)) {
            pageX = -CGFloat(direction) * width
        } completion: {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                dayOffset = max(-365, min(365, dayOffset + delta))
                pageX = CGFloat(direction) * width
            }
            Task { @MainActor in
                withAnimation(.easeOut(duration: 0.2)) { pageX = 0 }
            }
        }
    }

    /// Тап или протягивание по свободному месту сетки: задача создаётся сразу, название спрашивается следом.
    private func createTask(day: Int, start: Int, duration: Int) {
        let task = PlannerTask(
            title: "Новая задача",
            day: DayMath.day(offset: day),
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
            HStack(spacing: 12) {
                Text(toast.message)
                    .font(.system(size: 14))
                    .multilineTextAlignment(.leading)
                if let title = toast.actionTitle {
                    Button(title) {
                        toastAction?()
                        toastTask?.cancel()
                        self.toast = nil
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Tokens.accent)
                    .frame(minHeight: Tokens.hitTarget)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, toast.actionTitle == nil ? 10 : 2)
            .glassEffect(.regular.tint(Tokens.badge.opacity(0.7)), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
            .shadow(color: Color.black.opacity(0.4), radius: 12, y: 8)
            .padding(.horizontal, 16)
            .padding(.bottom, (zones["drawer"].map { rootSize.height - $0.minY } ?? Tokens.drawerCollapsed) + 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .allowsHitTesting(toast.actionTitle != nil)
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
            .position(x: ghostX(drag.location.x), y: max(drag.location.y - 46, 30))
            .allowsHitTesting(false)
        }
    }

    /// Карточка-призрак не вылезает за правый край экрана (как в прототипе).
    private func ghostX(_ fingerX: CGFloat) -> CGFloat {
        let half: CGFloat = 105
        guard rootSize.width > half * 2 + 16 else { return fingerX + 60 }
        return min(max(fingerX + 60, half + 8), rootSize.width - half - 8)
    }

    private func ghostMeta(_ drag: DragState) -> String {
        switch drag.target {
        case .grid(let day, let start):
            let time = ClockGrid.format(minutes: start) + "–" + ClockGrid.format(minutes: start + drag.duration)
            return visibleDays.count > 1 ? DayMath.label(offset: day).capitalizedFirst + " · " + time : time
        case .allDay(let day):
            return DayMath.label(offset: day).capitalizedFirst + " · весь день"
        case .dayTab(let offset):
            return mode == .day && !visibleDays.contains(offset)
                ? "Подержи — открою " + DayMath.label(offset: offset)
                : "На " + DayMath.label(offset: offset)
        case .backlog:
            return "В бэклог"
        case .quadrant(let raw):
            return Quadrant(rawValue: raw)?.name ?? "Не разобрано"
        case .project(let name):
            return name.map { "В проект «\($0)»" } ?? "Без проекта"
        case nil:
            return "Тащи на нужное время"
        }
    }

    // MARK: - Перетаскивание

    /// Сетка проехала сама или зоны поменялись — пересчитать цель под тем же пальцем.
    private func refreshDropTarget() {
        guard let state = drag else { return }
        let target = dropTarget(at: state.location, duration: state.duration, grab: state.grabOffsetY)
        if target != state.target { drag?.target = target }
    }

    private func dragChanged(_ task: PlannerTask, location: CGPoint, startLocation: CGPoint) {
        if drag == nil || drag?.taskID != task.id {
            var grab: CGFloat = min(CGFloat(task.duration) / 60 * Tokens.hourHeight / 2, 20)
            let fromTimeline = task.day != nil && task.start != nil
            if fromTimeline, let day = task.day, let start = task.start,
               let column = zones["grid-\(DayMath.offset(of: day))"], let viewport = zones["timeline"] {
                // Колонка сообщает рамку в координатах содержимого сетки; переводим в «planner».
                let blockTop = viewport.minY - gridScroll.offset + column.minY + gridTopInset + CGFloat(start) / 60 * Tokens.hourHeight
                grab = max(0, startLocation.y - blockTop)
            }
            drag = DragState(taskID: task.id, title: task.title, duration: task.duration, location: location,
                             grabOffsetY: grab, fromTimeline: task.day != nil, target: nil)
            selectedID = nil
            if drawerOpen && task.isInBacklog {
                withAnimation(.spring(duration: 0.3)) { drawerOpen = false }
            }
        }
        drag?.location = location
        let target = dropTarget(at: location, duration: task.duration, grab: drag?.grabOffsetY ?? 0)
        drag?.target = target
        updateSpring(for: target)
    }

    /// Система отменила жест: просто убрать призрак, ничего не переносить.
    private func dragCancelled() {
        drag = nil
        springTask?.cancel()
        springOffset = nil
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
        case .grid(let day, let start):
            task.day = DayMath.day(offset: day)
            task.start = start
            selectedID = task.id
        case .allDay(let day):
            task.day = DayMath.day(offset: day)
            task.start = nil
        case .dayTab(let offset):
            task.day = DayMath.day(offset: offset)
            showToast("«\(task.title)» — " + whenText(task))
        case .quadrant(let raw):
            guard raw != task.quadrantRaw else { return }
            task.quadrantRaw = raw
            showToast("«\(task.title)» → " + (Quadrant(rawValue: raw)?.name.lowercased() ?? "не разобрано"))
        case .project(let name):
            guard task.project?.name != name else { return }
            task.project = name.map { findOrCreateProject(named: $0) }
            showToast("«\(task.title)» → " + (name.map { "проект «\($0)»" } ?? "без проекта"))
        }
        NotificationScheduler.sync(tasks)
    }

    private func dropTarget(at point: CGPoint, duration: Int, grab: CGFloat) -> DropTarget? {
        if let drawer = zones["drawer"], drawer.contains(point) { return .backlog }
        for raw in 0...4 {
            if let cell = zones["quad-\(raw)"], cell.contains(point) { return .quadrant(raw) }
        }
        for (key, rect) in zones where key.hasPrefix("project-") && rect.contains(point) {
            let name = String(key.dropFirst("project-".count))
            return .project(name.isEmpty ? nil : name)
        }
        for (key, rect) in zones where key.hasPrefix("tab-") && rect.contains(point) {
            if let offset = Int(key.dropFirst(4)) { return .dayTab(offset: offset) }
        }
        for offset in visibleDays {
            if let allDay = zones["allday-\(offset)"], allDay.contains(point) { return .allDay(day: offset) }
        }
        guard let viewport = zones["timeline"], viewport.contains(point) else { return nil }
        // Колонки сетки сообщают рамки в координатах содержимого (они не меняются при прокрутке).
        let contentPoint = CGPoint(x: point.x - viewport.minX, y: point.y - viewport.minY + gridScroll.offset)
        for offset in visibleDays {
            if let column = zones["grid-\(offset)"], column.contains(contentPoint) {
                let y = contentPoint.y - grab - column.minY - gridTopInset
                let minutes = Int((y / Tokens.hourHeight * 60 / 15).rounded()) * 15
                return .grid(day: offset, start: ClockGrid.clampedStart(minutes, duration: duration))
            }
        }
        return nil
    }

    /// Задержка над вкладкой дня ~0,4 с открывает этот день.
    private func updateSpring(for target: DropTarget?) {
        guard mode == .day, case .dayTab(let offset) = target, offset != dayOffset else {
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

    private var streakInfo: Streak.Info { Streak.compute(tasks) }

    private func toggleDone(_ task: PlannerTask) {
        let firstToday = !task.isDone && !streakInfo.todayClosed
        task.isDone.toggle()
        task.completedAt = task.isDone ? Date() : nil
        if task.isDone {
            // Первая задача за день продлевает серию — говорим об этом в тосте.
            var message = "Готово: «\(task.title)»"
            if firstToday {
                let streak = Streak.compute(tasks).current
                message += " · 🔥 серия \(streak) " + DayMath.plural(streak, "день", "дня", "дней")
            }
            // Промахнулся — «Отменить» в тосте возвращает задачу в работу.
            showToast(message, actionTitle: "Отменить", duration: 4.5) {
                task.isDone = false
                task.completedAt = nil
            }
        }
        NotificationScheduler.sync(tasks)
    }

    /// Удалить задачу (свайп в бэклоге, корзина в редакторе).
    private func deleteTask(_ task: PlannerTask) {
        if selectedID == task.id { selectedID = nil }
        if editingTask?.id == task.id { editingTask = nil }
        let title = task.title
        context.delete(task)
        showToast("Удалил: «\(title)»")
        NotificationScheduler.sync(tasks.filter { $0.id != task.id })
    }

    private func resize(_ task: PlannerTask, to duration: Int) {
        task.duration = duration
        NotificationScheduler.sync(tasks)
    }

    /// Растягивание за верхний край: меняется начало, конец остаётся.
    private func retime(_ task: PlannerTask, start: Int, duration: Int) {
        task.start = start
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
        if !overdue.isEmpty {
            withAnimation(.spring(duration: 0.3)) { drawerOpen = true }
        }
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
        let quadrantNote = parsed.quadrant.map { " · " + $0.name.lowercased() } ?? ""
        showToast("«\(parsed.title)» — \(whenText(task))\(quadrantNote)")
        NotificationScheduler.sync(tasks + [task])
    }

    /// Сохранить надиктованные задачи: без дня — в бэклог (и открыть его), с днём — на сетку.
    private func addDrafts(_ drafts: [DraftTask]) {
        guard !drafts.isEmpty else { return }
        var rank = tasks.map { $0.backlogRank }.max() ?? 0
        var created: [PlannerTask] = []
        for draft in drafts {
            let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            rank += 1
            let name = draft.project.trimmingCharacters(in: .whitespacesAndNewlines)
            let task = PlannerTask(
                title: title.capitalizedFirst,
                day: draft.dayOffset.map { DayMath.day(offset: $0) },
                start: draft.start,
                duration: draft.duration,
                quadrant: Quadrant(rawValue: draft.quadrantRaw),
                project: name.isEmpty ? nil : findOrCreateProject(named: name.capitalizedFirst),
                backlogRank: rank
            )
            context.insert(task)
            created.append(task)
        }
        guard !created.isEmpty else { return }
        if created.contains(where: { $0.isInBacklog }) {
            withAnimation(.spring(duration: 0.3)) { drawerOpen = true }
        }
        let n = created.count
        showToast("Добавил \(n) " + DayMath.plural(n, "задачу", "задачи", "задач"))
        NotificationScheduler.sync(tasks + created)
    }

    private func whenText(_ task: PlannerTask) -> String {
        guard let day = task.day else { return "в бэклог" }
        let label = DayMath.label(offset: DayMath.offset(of: day))
        guard let start = task.start else { return label + " · весь день" }
        return label + " · " + ClockGrid.format(minutes: start) + "–" + ClockGrid.format(minutes: start + task.duration)
    }

    private func findOrCreateProject(named name: String) -> Project {
        let all = (try? context.fetch(FetchDescriptor<Project>())) ?? []
        if let existing = all.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            return existing
        }
        let project = Project(name: name.capitalizedFirst, colorIndex: all.count % ProjectPalette.colors.count)
        context.insert(project)
        return project
    }

    private func showToast(_ message: String, actionTitle: String? = nil, duration: Double = 2.8, action: (() -> Void)? = nil) {
        toastTask?.cancel()
        toast = ToastMessage(message: message, actionTitle: actionTitle)
        toastAction = action
        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(duration))
            if !Task.isCancelled {
                toast = nil
                toastAction = nil
            }
        }
    }
}

/// Сообщение внизу экрана; с `actionTitle` — кнопка (например, «Отменить»).
struct ToastMessage: Equatable {
    let id = UUID()
    let message: String
    let actionTitle: String?
}

extension String {
    var capitalizedFirst: String {
        guard let first = first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}
