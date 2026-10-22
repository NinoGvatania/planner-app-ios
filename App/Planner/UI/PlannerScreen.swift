import Foundation
import PlannerCore
import SwiftData
import SwiftUI
import UIKit

/// Единственный экран приложения: шапка, рабочая поверхность, панель бэклога.
struct PlannerScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \PlannerTask.createdAt) private var tasks: [PlannerTask]

    @State private var dayOffset = 0
    /// Период (день / неделя / месяц / год) и как его показывать (календарь / список / матрица / …).
    @State private var period: Period = .day
    @State private var display: Display = .calendar
    @State private var showDone = true
    @State private var drawerOpen = false
    @State private var showOverdue = false
    @State private var showVoice = false
    /// Чат-ассистент (микрофон, когда задан ключ Claude).
    @State private var showAssistant = false
    @State private var input = ""
    @State private var toast: ToastMessage?
    @State private var toastTask: Task<Void, Never>?
    @State private var toastAction: (() -> Void)?
    /// Высота плашки текущего тоста. Остаётся прежней и после того, как тост убран: пока он гаснет,
    /// место (над панелью или внутри неё) не меняется.
    @State private var toastPillHeight: CGFloat = 48
    @State private var selectedID: UUID?
    @State private var drag: DragState?
    @State private var zones: [String: CGRect] = [:]
    @State private var springTask: Task<Void, Never>?
    @State private var springOffset: Int?
    @State private var namingTask: PlannerTask?
    @State private var editingTask: PlannerTask?
    @State private var newTitle = ""
    @State private var rootSize: CGSize = .zero
    /// Полоска «домой» снизу: остров опускается к ней, раскрытый — заходит под неё.
    @State private var rootSafeBottom: CGFloat = 0
    /// Высота, доступная острову (с клавиатурой — до неё).
    @State private var islandSpace: CGFloat = 0
    /// Остров свернули, потому что из него взяли задачу: после переноса — раскрыть снова (по настройке).
    @State private var reopenBacklogAfterDrag = false
    @AppStorage(BacklogSettings.reopenKey) private var backlogReopens = true
    @State private var gridScroll = GridScroll()
    @State private var pagingLock = PagingLock()
    @State private var scrollToNowRequest = 0
    @State private var showProjects = false
    @State private var showSettings = false
    @State private var showStreak = false
    /// Фокус в строке ввода бэклога: только тогда экран уступает место клавиатуре.
    @FocusState private var inputFocused: Bool
    /// Дни страницы сетки, у которой развёрнута строка «весь день» (у уходящей при свайпе она не схлопывается).
    @State private var allDayExpandedDays: [Int]?
    /// Задачи, отмеченные сделанными прямо в листе «Просрочено»: остаются в нём, чтобы можно было вернуть.
    @State private var recentlyDoneOverdue: Set<UUID> = []
    @AppStorage("colorMode") private var colorModeRaw = ColorMode.quadrant.rawValue

    private let gridTopInset: CGFloat = 10

    private var today: Date { DayMath.today() }
    private var visibleTasks: [PlannerTask] { showDone ? tasks : tasks.filter { !$0.isDone } }
    private var overdueTasks: [PlannerTask] {
        tasks.filter { $0.isOverdue(today: today) }
            .sorted { ($0.day ?? today, $0.start ?? 0) < ($1.day ?? today, $1.start ?? 0) }
    }
    /// Для листа: просроченные плюс те, что только что отметили сделанными в нём (свайп «Вернуть»).
    private var overdueSheetTasks: [PlannerTask] {
        tasks.filter { $0.isOverdue(today: today) || recentlyDoneOverdue.contains($0.id) }
            .sorted { ($0.day ?? today, $0.start ?? 0) < ($1.day ?? today, $1.start ?? 0) }
    }
    /// Справочник для разбора диктовки: все проекты и названия 60 последних задач без повторов.
    private var voiceVocabulary: DictationVocabulary {
        let projects = ((try? context.fetch(FetchDescriptor<Project>())) ?? []).map(\.name)
        var seen = Set<String>()
        let titles = tasks.reversed().map(\.title).filter { seen.insert($0.lowercased()).inserted }
        return DictationVocabulary(projects: projects, recentTitles: Array(titles.prefix(60)))
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
    /// Понедельник текущей недели — точка отсчёта страниц недель.
    private var baseMonday: Int { DayMath.weekStartOffset(containing: 0) }
    /// Сетка дня показана (день + календарь): полоска недели, пружина на вкладках, прокрутка к «сейчас».
    private var isDayGrid: Bool { period == .day && display == .calendar }
    /// Дни, показанные на сетке: один в «Дне», неделя с понедельника в «Неделе».
    private var visibleDays: [Int] {
        period == .week && display == .calendar ? Array(weekStart...(weekStart + 6)) : [dayOffset]
    }
    private var monthAnchor: Date { DayMath.day(offset: dayOffset) }

    /// Номер страницы текущего периода (0 — период с сегодняшним днём).
    private var currentPeriodIndex: Int {
        switch period {
        case .day: return dayOffset
        case .week: return (weekStart - baseMonday) / 7
        case .month: return DayMath.monthDelta(from: today, to: monthAnchor)
        case .year: return DayMath.year(monthAnchor) - DayMath.year(today)
        }
    }

    private var periodIndex: Binding<Int> {
        Binding(get: { currentPeriodIndex }, set: { setPeriodIndex($0) })
    }

    /// Перелистнули период: день переезжает на ту же позицию соседнего периода.
    private func setPeriodIndex(_ index: Int) {
        let delta = index - currentPeriodIndex
        guard delta != 0 else { return }
        switch period {
        case .day: dayOffset = clampDay(dayOffset + delta)
        case .week: dayOffset = clampDay(dayOffset + delta * 7)
        case .month: dayOffset = clampDay(DayMath.offset(of: DayMath.date(monthAnchor, addingMonths: delta)))
        case .year: dayOffset = clampDay(DayMath.offset(of: DayMath.date(monthAnchor, addingYears: delta)))
        }
    }

    private func clampDay(_ value: Int) -> Int { max(-3650, min(3650, value)) }

    /// Копии рутин — на неделю вперёд и до конца открытого периода; кроме года — и следующего, чтобы
    /// при свайпе соседняя страница приезжала уже с рутинами.
    @discardableResult
    private func materializeRoutines() -> [PlannerTask] {
        let end = period == .year ? currentRange.end : pageRange(index: currentPeriodIndex + 1).end
        let lastDay = DayMath.calendar.date(byAdding: .day, value: -1, to: end) ?? end
        return RoutineManager.materialize(in: context, through: lastDay)
    }

    /// Границы периода страницы `index`: [start, end).
    private func pageRange(index: Int) -> (start: Date, end: Date) {
        switch period {
        case .day:
            return (DayMath.day(offset: index), DayMath.day(offset: index + 1))
        case .week:
            let first = baseMonday + index * 7
            return (DayMath.day(offset: first), DayMath.day(offset: first + 7))
        case .month:
            let start = DayMath.date(DayMath.monthStart(of: today), addingMonths: index)
            return (start, DayMath.date(start, addingMonths: 1))
        case .year:
            let start = DayMath.date(DayMath.yearStart(of: today), addingYears: index)
            return (start, DayMath.date(start, addingYears: 1))
        }
    }

    private var currentRange: (start: Date, end: Date) { pageRange(index: currentPeriodIndex) }

    /// Задачи календаря в периоде. Бэклог сюда не входит ни в одном виде: он живёт только в своей панели.
    private func filtered(_ source: [PlannerTask], in range: (start: Date, end: Date)) -> [PlannerTask] {
        source.filter { task in
            guard let day = task.day else { return false }
            return day >= range.start && day < range.end
        }
    }

    private var headerTitle: String {
        let range = currentRange
        switch period {
        case .day:
            return "\(DayMath.dayOfMonth(range.start)) \(DayMath.monthGenitive[DayMath.monthIndex(range.start)])"
        case .week:
            return rangeTitle(from: weekStart, to: weekStart + 6)
        case .month:
            return DayMath.monthNominative[DayMath.monthIndex(range.start)] + " \(DayMath.year(range.start))"
        case .year:
            return "\(DayMath.year(range.start))"
        }
    }

    private var headerSubtitle: String {
        let n = filtered(visibleTasks, in: currentRange).count
        let count = "\(n) " + DayMath.plural(n, "задача", "задачи", "задач")
        let scope: String
        switch period {
        case .day:
            let relative = dayOffset == 0 ? "сегодня" : (dayOffset == 1 ? "завтра" : (dayOffset == -1 ? "вчера" : ""))
            let weekday = DayMath.weekdayFull[DayMath.weekdayIndex(monthAnchor)].capitalizedFirst
            scope = relative.isEmpty ? weekday : weekday + ", " + relative
        case .week: scope = "Неделя"
        case .month: scope = "Месяц"
        case .year: scope = "Год"
        }
        return scope + " · " + count
    }

    /// Короткий подзаголовок для узких экранов: «Сегодня · 12 задач», «Пн · 3 задачи».
    private var headerShortSubtitle: String {
        guard period == .day else { return headerSubtitle }
        let n = filtered(visibleTasks, in: currentRange).count
        let count = "\(n) " + DayMath.plural(n, "задача", "задачи", "задач")
        let relative = dayOffset == 0 ? "Сегодня" : (dayOffset == 1 ? "Завтра" : (dayOffset == -1 ? "Вчера" : ""))
        let scope = relative.isEmpty ? DayMath.weekdayShort[DayMath.weekdayIndex(monthAnchor)].capitalizedFirst : relative
        return scope + " · " + count
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
        ZStack(alignment: .bottom) {
            // Размер берётся у GeometryReader: он задаётся системой и не зависит от содержимого.
            // Экран доходит до самого низа (под остров и полоску «домой») и не сжимается клавиатурой.
            GeometryReader { geometry in
                screen
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .top)
                    .onChange(of: geometry.size, initial: true) { _, size in rootSize = size }
                    .onChange(of: geometry.safeAreaInsets.bottom, initial: true) { _, inset in
                        // Только полоска «домой» (до 100 pt): высота клавиатуры сюда попадать не должна.
                        if inset < 100 { rootSafeBottom = inset }
                    }
            }
            .ignoresSafeArea([.container, .keyboard], edges: .bottom)

            // Остров висит над экраном; с клавиатурой поднимается только он, и только для своей строки ввода
            // (клавиатура алерта «Новая задача» или листа его не двигает).
            islandLayer
                .ignoresSafeArea(inputFocused ? .container : [.container, .keyboard], edges: .bottom)
        }
        .coordinateSpace(name: "planner")
        .onPreferenceChange(ZoneFramesKey.self) { frames in
            zones = frames
            // Верх сетки на случай, когда «timeline» молчит (свайп): последнее известное значение.
            if let timeline = frames["timeline"] { gridScroll.viewportMinY = timeline.minY }
        }
        .onChange(of: zones) { _, _ in refreshDropTarget() }
        .overlay(alignment: .topLeading) { ghostView }
    }

    /// Зазор под свёрнутым островом: опущен к полоске «домой», с клавиатурой — сразу над ней.
    private var islandGap: CGFloat { inputFocused ? 6 : max(6, rootSafeBottom - 14) }

    /// Сколько снизу страницы закрывает свёрнутый остров (без клавиатуры): прокрутка заходит под него,
    /// месяц и матрица заканчиваются над ним. Раскрытый остров страницы не сжимает — ложится поверх.
    private var islandInset: CGFloat { Tokens.islandCollapsed + max(6, rootSafeBottom - 14) + 8 }

    private var islandLayer: some View {
        BacklogDrawerView(
            tasks: backlogTasks,
            isOpen: $drawerOpen,
            input: $input,
            onSubmit: submitInput,
            // С ключом Claude микрофон открывает чат-ассистента, без него — диктовку с разбором как раньше.
            onVoice: { if ClaudeSettings.isEnabled { showAssistant = true } else { showVoice = true } },
            onToggle: toggleDone,
            drag: drag,
            onDragChanged: dragChanged,
            onDragEnded: dragEnded,
            onEdit: { editingTask = $0 },
            onDelete: deleteTask,
            maxHeight: islandMaxHeight,
            bottomPadding: inputFocused ? 6 : max(8, rootSafeBottom - 12),
            floatingGap: islandGap,
            onDragCancelled: dragCancelled,
            overdueCount: overdueTasks.count,
            onOverdue: { showOverdue = true },
            inputFocus: $inputFocused
        )
        .overlay(alignment: toastAboveDrawer ? .top : .bottom) { toastLayer }
        // Число строк бэклога меняет высоту раскрытого острова — той же пружиной.
        .animation(.spring(duration: 0.3), value: backlogTasks.count)
        .animation(.easeOut(duration: 0.22), value: toast)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { islandSpace = $0 }
    }

    /// Раскрытый остров — не выше половины экрана; с клавиатурой — чтобы шапка оставалась видна.
    private var islandMaxHeight: CGFloat {
        guard rootSize.height > 0 else { return .infinity }
        let half = rootSize.height * 0.5
        let room = islandSpace > 0 ? islandSpace - 62 - (isDayGrid ? 64 : 0) - 12 : half
        return max(Tokens.islandCollapsed + 74, min(half, room))
    }

    private var screen: some View {
        VStack(spacing: 0) {
            HeaderView(
                title: headerTitle,
                subtitle: headerSubtitle,
                shortSubtitle: headerShortSubtitle,
                streak: streakInfo.current,
                todayNumber: DayMath.dayOfMonth(today),
                period: Binding(
                    get: { period },
                    set: { value in withAnimation(.easeOut(duration: 0.2)) { period = value } }
                ),
                display: Binding(
                    get: { display },
                    set: { value in withAnimation(.easeOut(duration: 0.2)) { display = value } }
                ),
                showDone: Binding(
                    get: { showDone },
                    set: { value in withAnimation(.spring(duration: 0.3)) { showDone = value } }
                ),
                colorMode: Binding(
                    get: { ColorMode(rawValue: colorModeRaw) ?? .quadrant },
                    set: { colorModeRaw = $0.rawValue }
                ),
                onStreak: { showStreak = true },
                onToday: {
                    withAnimation { dayOffset = 0 }
                    scrollToNowRequest += 1
                },
                onProjects: { showProjects = true },
                onSettings: { showSettings = true }
            )

            if isDayGrid {
                WeekStripView(dayOffset: $dayOffset, hasTasks: { offset in
                    let date = DayMath.day(offset: offset)
                    return visibleTasks.contains { $0.day == date }
                }, hoveredOffset: hoveredTab, blocked: { drag != nil }, dragging: drag != nil)
            }

            // Все виды листаются одинаково: соседние периоды отрисованы рядом, страница едет за пальцем.
            PagerView(
                index: periodIndex,
                blocked: { drag != nil || gridScroll.interacting || pagingLock.locked },
                cancelWhen: drag != nil,
                hintKey: display == .calendar && period == .month ? "month" : nil,
                keyed: !(display == .calendar && (period == .day || period == .week)),
                minVisibleHeight: pageMinHeight
            ) { index, live, tick in
                page(index: index, live: live, tick: tick)
            }
        }
        .background(Tokens.background.ignoresSafeArea())
        .foregroundStyle(Tokens.text)
        .sheet(isPresented: $showOverdue, onDismiss: { recentlyDoneOverdue = [] }) {
            OverdueSheet(
                tasks: overdueSheetTasks,
                onToggle: toggleDone,
                onFitToday: overdueToToday,
                onFitTomorrow: { fitOverdue(dayOffset: 1) },
                onToBacklog: overdueToBacklog,
                onDelete: deleteTask,
                onChanged: { NotificationScheduler.sync(tasks) }
            )
        }
        .task {
            SeedData.seedIfNeeded(in: context)
            SeedData.assignProjectColorsIfNeeded(in: context)
            let created = materializeRoutines()
            NotificationScheduler.requestPermission()
            NotificationScheduler.sync(tasks + created)
        }
        .onChange(of: scenePhase) { _, phase in
            // Вернулись в приложение (возможно, уже другой день): досоздать рутины, обновить напоминания.
            guard phase == .active else { return }
            let created = materializeRoutines()
            NotificationScheduler.sync(tasks + created)
        }
        // Листаешь периоды вперёд — рутины появляются и там, а не только на ближайшей неделе.
        .onChange(of: currentRange.end) { _, _ in
            let created = materializeRoutines()
            if !created.isEmpty { NotificationScheduler.sync(tasks + created) }
        }
        .onChange(of: period) { _, _ in resetInteraction() }
        .onChange(of: display) { _, _ in resetInteraction() }
        .fullScreenCover(isPresented: $showVoice) {
            VoiceInputSheet(onDone: addDrafts, vocabulary: voiceVocabulary)
        }
        .fullScreenCover(isPresented: $showAssistant) {
            AssistantChatView(onAdd: addDrafts, vocabulary: voiceVocabulary)
        }
        .sheet(isPresented: $showProjects) {
            ProjectsSheet()
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet()
        }
        .sheet(isPresented: $showStreak) {
            StreakSheet(
                info: streakInfo,
                done: tasks.filter(\.isDone).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) },
                onRestore: toggleDone
            )
        }
        .sheet(item: $editingTask) { task in
            TaskEditSheet(
                task: task,
                onDelete: { deleteTask(task) },
                // Включили «Повторять» или поменяли расписание — копии и до конца открытого периода.
                onChanged: { NotificationScheduler.sync(tasks + materializeRoutines()) }
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

    /// Сменили период или режим: выделение и перенос сбрасываются.
    private func resetInteraction() {
        selectedID = nil
        allDayExpandedDays = nil
        drag = nil
        springTask?.cancel()
        springOffset = nil
    }

    // MARK: - Страницы

    /// Содержимое страницы `index` текущего периода в текущем режиме. `live` — средняя страница пейджера.
    @ViewBuilder
    private func page(index: Int, live: Bool, tick: Int) -> some View {
        let range = pageRange(index: index)
        switch display {
        case .calendar:
            switch period {
            case .day:
                // Сетке дня нельзя менять идентичность: «пружина» на вкладке подменяет день посреди переноса.
                timeline(days: [index], live: live, tick: tick)
            case .week:
                let first = baseMonday + index * 7
                timeline(days: Array(first...(first + 6)), live: live, tick: tick)
            case .month:
                MonthView(
                    anchor: range.start,
                    tasks: visibleTasks,
                    drag: drag,
                    live: live,
                    onSelectDay: { offset in
                        withAnimation(.easeOut(duration: 0.2)) {
                            dayOffset = offset
                            period = .day
                        }
                    },
                    onEdit: { editingTask = $0 },
                    onCreate: createAllDayTask,
                    onDragChanged: dragChanged,
                    onDragEnded: dragEnded,
                    onDragCancelled: dragCancelled
                )
                // Месяц заканчивается над свёрнутым островом; раскрытый остров ложится поверх, месяц не сжимается.
                .padding(.bottom, islandInset)
                .id(index)
            case .year:
                YearView(year: DayMath.year(range.start), tasks: visibleTasks) { start in
                    withAnimation(.easeOut(duration: 0.2)) {
                        dayOffset = DayMath.offset(of: start)
                        period = .month
                    }
                }
                .contentMargins(.bottom, islandInset, for: .scrollContent)
                .id(index)
            }
        case .list:
            // `.id(index)`: страница другого периода начинает со свежим состоянием (свёрнутые секции,
            // открытый квадрант), а не наследует его от подменённой.
            PeriodListView(
                tasks: visibleTasks, range: range, period: period, drag: drag, live: live,
                onToggle: toggleDone, onDragChanged: dragChanged, onDragEnded: dragEnded,
                onEdit: { editingTask = $0 }, onDragCancelled: dragCancelled
            )
            // Прокрутка заходит под полупрозрачный остров, последние строки докручиваются над ним.
            .contentMargins(.bottom, islandInset, for: .scrollContent)
            .id(index)
        case .matrix:
            MatrixView(
                tasks: filtered(tasks, in: range), drag: drag,
                onToggle: toggleDone, onDragChanged: dragChanged, onDragEnded: dragEnded,
                onEdit: { editingTask = $0 }, onDelete: deleteTask, onDragCancelled: dragCancelled,
                live: live, lock: pagingLock
            )
            .padding(.bottom, islandInset)
            .id(index)
        case .projects:
            ProjectsView(
                tasks: filtered(visibleTasks, in: range), drag: drag,
                onToggle: toggleDone, onDragChanged: dragChanged, onDragEnded: dragEnded,
                onEdit: { editingTask = $0 }, onManageProjects: { showProjects = true },
                onDragCancelled: dragCancelled, live: live
            )
            // Доска проектов при удержании должна целиком быть над островом — поэтому отступ, а не прокрутка под ним.
            .padding(.bottom, islandInset)
            .id(index)
        case .chart:
            DashboardView(tasks: filtered(tasks, in: range), onOpenProjects: { showProjects = true })
                .contentMargins(.bottom, islandInset, for: .scrollContent)
                .id(index)
        }
    }

    private func timeline(days: [Int], live: Bool, tick: Int) -> some View {
        DayTimelineView(
            days: days,
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
            onSelectDay: { offset in
                withAnimation(.easeOut(duration: 0.2)) {
                    dayOffset = offset
                    period = .day
                }
            },
            live: live,
            syncTick: tick,
            scroll: gridScroll,
            onAutoScrollTick: refreshDropTarget,
            scrollToNowRequest: scrollToNowRequest,
            onDragCancelled: dragCancelled,
            allDayExpanded: Binding(
                get: { allDayExpandedDays == days },
                set: { allDayExpandedDays = $0 ? days : nil }
            ),
            islandInset: islandInset,
            islandTop: zones["drawer"]?.minY ?? .infinity
        )
    }

    /// Удержание на дне в месяце: задача на весь день, название спрашивается следом.
    private func createAllDayTask(day: Int) {
        let task = PlannerTask(
            title: "Новая задача",
            day: DayMath.day(offset: day),
            start: nil,
            backlogRank: (tasks.map { $0.backlogRank }.max() ?? 0) + 1
        )
        context.insert(task)
        newTitle = ""
        namingTask = task
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

    /// Над панелью бэклога хватает места для тоста (шапка и полоска недели не задеты).
    private var toastAboveDrawer: Bool {
        let drawerTop = zones["drawer"]?.minY ?? (rootSize.height - Tokens.islandCollapsed)
        let chrome: CGFloat = 62 + (isDayGrid ? 64 : 0)
        return drawerTop - chrome >= toastPillHeight + 12 + 8
    }

    /// Высота плашки тоста заранее, до показа: текст 14 pt до трёх строк, поля 10 (с кнопкой — строка 44).
    private func toastHeight(_ toast: ToastMessage) -> CGFloat {
        let font = UIFont.systemFont(ofSize: 14)
        let action = toast.actionTitle.map {
            ($0 as NSString).size(withAttributes: [.font: UIFont.boldSystemFont(ofSize: 14)]).width + 12
        } ?? 0
        let width = max(60, rootSize.width - 32 - 28 - action)
        let text = (toast.message as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        ).height
        let lines = min(3, max(1, (text / font.lineHeight).rounded()))
        let textHeight = lines * font.lineHeight
        return toast.actionTitle == nil ? textHeight + 20 : max(Tokens.hitTarget, textHeight) + 4
    }

    /// Минимальная высота страницы пейджера, при которой она видна целиком по смыслу (см. `PagerView`).
    private var pageMinHeight: CGFloat {
        switch (display, period) {
        case (.calendar, .week): return 48 + Tokens.hitTarget + 1
        // Месяц: заголовок дней 22 + линия + шесть строк по 24 (кружок числа; верхний отступ клетка отдаёт сама).
        case (.calendar, .month): return 22 + 1 + 6 * 24
        // Переключатель «Матрица / Список» с отступом (до 48), строка капсул 44 и поле снизу 10.
        case (.matrix, _): return 48 + Tokens.hitTarget + 10
        default: return 60
        }
    }

    /// Тост висит на панели бэклога и едет вместе с ней: в 12 pt над её верхом, а если выше места нет
    /// (панель на весь экран, клавиатура) — внутри панели прямо над строкой ввода. Переход только у самой
    /// плашки: 14 pt и прозрачность, как в прототипе, а не пролёт через всю панель.
    private var toastLayer: some View {
        ZStack {
            if let toast = toast {
                toastPill(toast)
                    .transition(.offset(y: 14).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, toastAboveDrawer ? 0 : 60 + 8)
        .alignmentGuide(.top) { $0[.bottom] + 12 }
    }

    private func toastPill(_ toast: ToastMessage) -> some View {
        HStack(spacing: 12) {
            Text(toast.message)
                .font(.system(size: 14))
                .multilineTextAlignment(.leading)
                .lineLimit(3)
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
        // Сплошной фон по форме обводки (как у плашки переноса): стекло с тенью выходило за рамку.
        .background(Tokens.badge, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .shadow(color: Color.black.opacity(0.4), radius: 12, y: 8)
        .allowsHitTesting(toast.actionTitle != nil)
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
            // Сплошной фон ровно по форме рамки, как в прототипе: стекло рисовало серую подложку
            // больше самой плашки, и она торчала за зелёной рамкой.
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
            return isDayGrid && !visibleDays.contains(offset)
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
               let column = zones["grid-\(DayMath.offset(of: day))"],
               let viewportMinY = zones["timeline"]?.minY ?? gridScroll.viewportMinY {
                // Колонка сообщает рамку в координатах содержимого сетки; переводим в «planner».
                let blockTop = viewportMinY - gridScroll.offset + column.minY + gridTopInset + CGFloat(start) / 60 * Tokens.hourHeight
                grab = max(0, startLocation.y - blockTop)
            }
            drag = DragState(taskID: task.id, title: task.title, duration: task.duration, location: location,
                             grabOffsetY: grab, fromTimeline: task.day != nil, target: nil)
            selectedID = nil
            if drawerOpen {
                // Остров уступает место любому переносу: раскрытый, он закрывал бы цели внизу экрана.
                // После переноса — раскрыть снова, если так выбрано в настройках.
                reopenBacklogAfterDrag = true
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
        reopenBacklogIfNeeded()
    }

    /// Задачу брали из раскрытого бэклога — после переноса он раскрывается снова (или остаётся свёрнутым).
    private func reopenBacklogIfNeeded() {
        guard reopenBacklogAfterDrag else { return }
        reopenBacklogAfterDrag = false
        if backlogReopens {
            withAnimation(.spring(duration: 0.3)) { drawerOpen = true }
        }
    }

    private func dragEnded() {
        guard let state = drag else { return }
        drag = nil
        springTask?.cancel()
        springOffset = nil
        reopenBacklogIfNeeded()
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
            // Из бэклога задача в матрицу периода не переезжает — меняется только квадрант.
            showToast("«\(task.title)» → " + (Quadrant(rawValue: raw)?.name.lowercased() ?? "не разобрано")
                      + (task.isInBacklog ? " · в бэклоге" : ""))
        case .project(let name):
            guard task.project?.name != name else { return }
            task.project = name.map { findOrCreateProject(named: $0) }
            showToast("«\(task.title)» → " + (name.map { "проект «\($0)»" } ?? "без проекта")
                      + (task.isInBacklog ? " · в бэклоге" : ""))
        }
        NotificationScheduler.sync(tasks)
    }

    private func dropTarget(at point: CGPoint, duration: Int, grab: CGFloat) -> DropTarget? {
        // Остров и всё под ним (зазор до края экрана, клавиатура) — бэклог: сетка там скрыта, бросать в неё нельзя.
        if let drawer = zones["drawer"], drawer.contains(point) || point.y >= drawer.minY { return .backlog }
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
        guard isDayGrid, case .dayTab(let offset) = target, offset != dayOffset else {
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
        let wasOverdue = task.isOverdue(today: today)
        task.isDone.toggle()
        task.completedAt = task.isDone ? Date() : nil
        if task.isDone, wasOverdue, showOverdue {
            recentlyDoneOverdue.insert(task.id)
        }
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
                // Вернуть напоминание, событие в календаре и снимок виджета.
                NotificationScheduler.sync(tasks)
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

    /// «На завтра»: просроченные — в свободные окна дня `target` с 9:00 (сегодня — `overdueToToday`).
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
        period = .day
        display = .calendar
        dayOffset = target
        selectedID = nil
        let times = placed.sorted().map { ClockGrid.format(minutes: $0) }.joined(separator: ", ")
        var message = placed.isEmpty ? "Свободных окон нет" : (target == 0 ? "Разложил на сегодня: " : "Перенёс на завтра: ") + times
        if left > 0 { message += " · не влезло \(left) — в бэклоге" }
        showToast(message)
        NotificationScheduler.sync(tasks)
    }

    /// «На сегодня»: все просроченные — на сегодня на весь день, без времени; время расставляешь сам.
    private func overdueToToday() {
        let overdue = overdueTasks
        guard !overdue.isEmpty else {
            showOverdue = false
            showToast("Просроченных задач нет")
            return
        }
        let today = DayMath.day(offset: 0)
        for task in overdue {
            task.day = today
            task.start = nil
        }
        showOverdue = false
        period = .day
        display = .calendar
        dayOffset = 0
        selectedID = nil
        let n = overdue.count
        showToast("На сегодня, на весь день: \(n) " + DayMath.plural(n, "задача", "задачи", "задач"))
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
            if offset == 0 { overdueToToday() } else { fitOverdue(dayOffset: offset) }
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
        if let offset = parsed.dayOffset, isDayGrid, (0...6).contains(offset) {
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
                backlogRank: rank,
                notes: draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)
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
        if let existing = all.first(where: { $0.matches(name) }) {
            return existing
        }
        let project = Project(name: name.capitalizedFirst, colorIndex: all.count % ProjectPalette.colors.count)
        context.insert(project)
        return project
    }

    private func showToast(_ message: String, actionTitle: String? = nil, duration: Double = 2.8, action: (() -> Void)? = nil) {
        toastTask?.cancel()
        let next = ToastMessage(message: message, actionTitle: actionTitle)
        toastPillHeight = toastHeight(next)
        toast = next
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
