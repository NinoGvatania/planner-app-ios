import PlannerCore
import SwiftUI

enum HandleEdge { case top, bottom }

/// Активное растягивание ручкой: обычный класс, не Observable — читается из цикла автопрокрутки
/// и из жеста, не перерисовывая сетку на каждое касание.
final class ResizeTracker {
    var edge: HandleEdge?
    var originalStart = 0
    var originalEnd = 0
    /// Последнее положение пальца в координатах «planner».
    var fingerY: CGFloat = 0
    /// Насколько палец был ниже кромки блока в момент захвата (в координатах содержимого).
    var grab: CGFloat = 0
}

/// Создание удержанием с протягиванием: где начали и где палец. Обычный класс — читается и из жеста,
/// и из цикла автопрокрутки (сетка едет под неподвижным пальцем, силуэт должен расти вместе с ней).
final class CreateTracker {
    var day: Int?
    /// Начало в координатах содержимого сетки.
    var startY: CGFloat = 0
    /// Последнее положение пальца в координатах «planner».
    var fingerY: CGFloat = 0
}

/// Сетка 0:00–24:00 на один или три дня: строка «весь день», колонки дней, блоки задач.
/// Тап по блоку выделяет его (второй тап — редактор), ручка снизу растягивает, удержание начинает
/// перетаскивание; тап по свободному месту создаёт задачу, удержание с протягиванием — задачу нужной длины.
/// У верхнего и нижнего края сетка прокручивается сама, пока тянут или растягивают.
struct DayTimelineView: View {
    /// Смещения дней от сегодняшнего: один день или три подряд.
    let days: [Int]
    let tasks: [PlannerTask]
    @Binding var selectedID: UUID?
    let drag: DragState?
    let onToggle: (PlannerTask) -> Void
    let onResize: (PlannerTask, Int) -> Void
    /// Растягивание за верхний край: (задача, новое начало, новая длительность).
    let onRetime: (PlannerTask, Int, Int) -> Void
    /// (задача, где палец, где палец был в начале) в координатах «planner».
    let onDragChanged: (PlannerTask, CGPoint, CGPoint) -> Void
    let onDragEnded: () -> Void
    /// Создать задачу: (день, начало, длительность).
    let onCreate: (Int, Int, Int) -> Void
    let onEdit: (PlannerTask) -> Void
    /// Тап по заголовку дня в неделе — открыть этот день.
    var onSelectDay: ((Int) -> Void)? = nil
    /// Средняя страница пейджера: только она сообщает зоны сброса и пишет общее смещение прокрутки.
    /// Соседние страницы подравнивают свою прокрутку под общую при каждом `syncTick`.
    var live = true
    var syncTick = 0
    /// Смещение прокрутки сетки, общее с экраном (для зон сброса).
    let scroll: GridScroll
    /// Сетка проехала сама под неподвижным пальцем — экран пересчитывает цель сброса.
    var onAutoScrollTick: (() -> Void)? = nil
    /// Увеличивается, когда нужно прокрутить к текущему времени (кнопка «к сегодня»).
    var scrollToNowRequest: Int = 0
    var onDragCancelled: (() -> Void)? = nil
    /// Строка задач без времени развёрнута (иначе — одна задача и «+N»). Хранится у экрана по дням страницы:
    /// уходящая при свайпе страница не схлопывает панель на лету, новая начинает свёрнутой.
    @Binding var allDayExpanded: Bool
    /// Сколько снизу закрывает свёрнутый остров: сетка прокручивается под ним, у края переноса — его верх.
    var islandInset: CGFloat = 0

    @State private var liveDuration: Int?
    @State private var liveStart: Int?
    /// Силуэт создаваемой задачи, пока тянут по свободному месту.
    @State private var creating: (day: Int, start: Int, duration: Int)?
    /// Удержание началось на блоке или его ручке: это перенос или растягивание, а не создание.
    @State private var creationSuppressed = false
    @State private var scrollPosition = ScrollPosition(edge: .top)
    @State private var scrolledToNow = false
    /// Видимая область сетки в координатах «planner».
    @State private var viewport: CGRect = .zero
    @Environment(\.pagerSwiping) private var pagerSwiping
    @State private var autoScroll: Task<Void, Never>?
    @State private var autoScrollDirection = 0
    @State private var resizeTracker = ResizeTracker()
    @State private var createTracker = CreateTracker()
    @State private var allDayScroll = ScrollPosition(edge: .top)

    private let topInset: CGFloat = 10
    private let bottomInset: CGFloat = 26
    private let gridHeight = 24 * Tokens.hourHeight
    private var contentHeight: CGFloat { topInset + gridHeight + bottomInset }
    private var compactColumns: Bool { days.count > 1 }
    /// Сетка недели: семь узких колонок, подписи и чипы без лишних элементов.
    private var narrowColumns: Bool { days.count >= 5 }

    private func date(_ offset: Int) -> Date { DayMath.day(offset: offset) }

    /// Перетаскиваемая задача, чей день сейчас не виден (день переключился во время перетаскивания):
    /// её блок остаётся в первой колонке невидимым, чтобы жест не оборвался.
    private var phantom: PlannerTask? {
        guard let drag = drag, let task = tasks.first(where: { $0.id == drag.taskID }), let day = task.day,
              !days.contains(DayMath.offset(of: day)) else { return nil }
        return task
    }

    private func timed(column index: Int, day offset: Int) -> [PlannerTask] {
        let day = date(offset)
        var list = tasks.filter { $0.day == day && $0.start != nil }
        if index == 0, let phantom = phantom, phantom.start != nil { list.append(phantom) }
        return list
    }

    private func allDay(column index: Int, day offset: Int) -> [PlannerTask] {
        let day = date(offset)
        var list = tasks.filter { $0.day == day && $0.start == nil }
        if index == 0, let phantom = phantom, phantom.start == nil { list.append(phantom) }
        return list
    }

    private func duration(of task: PlannerTask) -> Int {
        task.id == selectedID ? (liveDuration ?? task.duration) : task.duration
    }

    private func start(of task: PlannerTask) -> Int {
        task.id == selectedID ? (liveStart ?? task.start ?? 0) : (task.start ?? 0)
    }

    private func placements(_ list: [PlannerTask], day: Date) -> [String: LanePlacement] {
        let items = list
            .filter { $0.day == day }
            .map { LayoutItem(id: $0.id.uuidString, start: start(of: $0), duration: duration(of: $0)) }
        var result: [String: LanePlacement] = [:]
        for placement in DayLayout.lanes(for: items) {
            result[placement.id] = placement
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            if compactColumns {
                dayHeaders
            }
            allDayRow
            Rectangle().fill(Tokens.line).frame(height: 1)
            GeometryReader { geometry in
                let areaWidth = max(0, geometry.size.width - Tokens.gutter - 8)
                ScrollView(.vertical, showsIndicators: false) {
                    grid(areaWidth: areaWidth)
                }
                .scrollPosition($scrollPosition)
                .contentMargins(.bottom, islandInset, for: .scrollContent)
                .onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, offset in
                    if live { scroll.offset = offset }
                }
                // Нужна только высота и вертикаль: без `x` свайп страницы вбок не перерисовывает сетку на каждом кадре.
                .onGeometryChange(for: CGRect.self) { proxy in
                    let frame = proxy.frame(in: .named("planner"))
                    return CGRect(x: 0, y: frame.minY, width: 0, height: frame.height)
                } action: { frame in
                    viewport = frame
                    scrollToNowIfNeeded()
                }
                .reportZone("timeline", enabled: live && !pagerSwiping)
            }
        }
        .onChange(of: drag?.location) { _, location in
            guard live else { return }
            if let location = location {
                updateAutoScroll(fingerY: location.y)
            } else {
                stopAutoScroll()
            }
        }
        .onChange(of: scrollToNowRequest) { _, _ in
            guard live else { return }
            withAnimation(.easeOut(duration: 0.25)) { scrollToNow() }
        }
        .onChange(of: syncTick) { _, _ in
            // Начался свайп между днями: соседняя страница встаёт на ту же прокрутку, что и средняя.
            if !live { scrollPosition.scrollTo(y: scroll.offset) }
        }
        .onChange(of: allDayHidden) { _, hidden in
            // Лишние задачи без времени ушли (на сетку, в бэклог, сделаны): прятать больше нечего —
            // панель сворачивается сама, а не висит пустой без кнопки.
            if hidden == 0, allDayExpanded {
                withAnimation(.easeOut(duration: 0.2)) { allDayExpanded = false }
            }
        }
        .onDisappear { stopAutoScroll() }
    }

    // MARK: - Прокрутка

    private func scrollToNowIfNeeded() {
        guard !scrolledToNow, viewport.height > 0 else { return }
        scrolledToNow = true
        if live, scroll.offset == 0 {
            DispatchQueue.main.async { scrollToNow() }
        } else {
            // Соседняя страница или возврат к сетке: та же прокрутка, что у экрана.
            let offset = scroll.offset
            DispatchQueue.main.async { scrollPosition.scrollTo(y: offset) }
        }
    }

    /// Текущий час минус один — вверху видимой области, с тем же отступом сверху, что у «0:00»:
    /// подпись часа целиком видна под разделителем, а не срезана пополам.
    private func scrollToNow() {
        let hour = max(0, min(23, DayMath.nowMinutes() / 60 - 1))
        let y = min(CGFloat(hour) * Tokens.hourHeight, max(0, contentHeight + islandInset - viewport.height))
        scrollPosition.scrollTo(y: y)
    }

    /// У края видимой области (52 pt) сетка едет сама по 12 pt за кадр, как в прототипе.
    private func updateAutoScroll(fingerY: CGFloat) {
        let edge: CGFloat = 52
        var direction = 0
        // Низ видимой сетки — верх острова: ниже палец уже над бэклогом.
        let visibleBottom = viewport.maxY - islandInset
        if viewport.height > 0, fingerY >= viewport.minY, fingerY <= visibleBottom {
            if fingerY < viewport.minY + edge {
                direction = -1
            } else if fingerY > visibleBottom - edge {
                direction = 1
            }
        }
        guard direction != autoScrollDirection else { return }
        autoScrollDirection = direction
        autoScroll?.cancel()
        autoScroll = nil
        guard direction != 0 else { return }
        autoScroll = Task { @MainActor in
            var y = scroll.offset
            while !Task.isCancelled {
                let limit = max(0, contentHeight + islandInset - viewport.height)
                let next = max(0, min(limit, y + CGFloat(direction) * 12))
                if next == y { break }
                y = next
                scrollPosition.scrollTo(y: y)
                scroll.offset = y
                if resizeTracker.edge != nil { applyResize(plannerY: resizeTracker.fingerY) }
                if let day = createTracker.day, creating != nil, !creationSuppressed {
                    updateCreating(day: day, startY: createTracker.startY, endY: gridY(fromPlannerY: createTracker.fingerY))
                }
                onAutoScrollTick?()
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    private func stopAutoScroll() {
        autoScrollDirection = 0
        autoScroll?.cancel()
        autoScroll = nil
    }

    /// Координата «planner» → координата содержимого сетки.
    private func gridY(fromPlannerY y: CGFloat) -> CGFloat {
        y - viewport.minY + scroll.offset
    }

    // MARK: - Заголовки дней (3 дня)

    private var dayHeaders: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: Tokens.gutter, height: 48)
            ForEach(days, id: \.self) { offset in
                let date = date(offset)
                let hovered = drag?.target == .dayTab(offset: offset)
                VStack(spacing: 2) {
                    Text(DayMath.weekdayShort[DayMath.weekdayIndex(date)])
                        .font(.system(size: 11))
                        .foregroundStyle(offset == 0 ? Tokens.accent
                                         : (DayMath.isWeekend(date) ? Tokens.weekend.opacity(offset < 0 ? 0.5 : 0.85)
                                            : (offset < 0 ? Tokens.muted : Tokens.caption)))
                    Text("\(DayMath.dayOfMonth(date))")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Tokens.dayNumber(isToday: offset == 0, isWeekend: DayMath.isWeekend(date), isPast: offset < 0))
                        .frame(minWidth: 28, minHeight: 28)
                        .background(offset == 0 ? Tokens.accent : Color.clear, in: Capsule())
                }
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(hovered ? Tokens.accent.opacity(0.22) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
                .contentShape(Rectangle())
                .onPageTap { onSelectDay?(offset) }
                .reportZone("tab-\(offset)", enabled: live && drag != nil)
                .accessibilityLabel(DayMath.accessibilityLabel(offset: offset))
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Открыть день")
            }
        }
        .padding(.trailing, 8)
        .contentShape(Rectangle())
    }

    // MARK: - Весь день

    /// Задач без времени на показанных днях (без фантомов).
    private var allDayTotal: Int {
        days.reduce(0) { sum, day in
            let date = date(day)
            return sum + tasks.filter { $0.day == date && $0.start == nil }.count
        }
    }

    /// Сколько задач без времени прячется за первой в каждой колонке.
    private var allDayHidden: Int {
        days.reduce(0) { sum, day in
            let date = date(day)
            return sum + max(0, tasks.filter { $0.day == date && $0.start == nil }.count - 1)
        }
    }

    private var allDayChipHeight: CGFloat { narrowColumns ? 24 : 28 }

    /// Развёрнутая панель показывается, только пока в какой-то колонке есть спрятанные задачи.
    private var allDayPanelShown: Bool { allDayExpanded && allDayHidden > 0 }

    /// Строк в самой длинной колонке (без невидимых фантомов переноса).
    private var allDayMaxRows: Int {
        days.map { day in
            let date = date(day)
            return tasks.filter { $0.day == date && $0.start == nil }.count
        }.max() ?? 1
    }

    /// Высота развёрнутой панели: до пяти строк, дальше — прокрутка внутри панели, сетка не страдает.
    private var allDayExpandedHeight: CGFloat {
        CGFloat(min(max(allDayMaxRows, 1), 5)) * (allDayChipHeight + 4) + 8
    }

    /// Строка без времени: слева одна кнопка-счётчик («+7» / число), справа колонки. Свёрнутая — 44 pt,
    /// фишка по центру; развёрнутая — отдельная панель с прокруткой, не выше пяти строк, с отступом от сетки.
    /// Устройство строки в обоих состояниях одно и то же (меняются только размеры и фон): фишка, которую
    /// тянут, не пересоздаётся, когда панель раскрывается или сворачивается посреди переноса.
    private var allDayRow: some View {
        let shown = allDayPanelShown
        return HStack(alignment: .top, spacing: 0) {
            allDayBadge
            ScrollView(.vertical, showsIndicators: false) {
                allDayColumns
            }
            .scrollPosition($allDayScroll)
            .scrollDisabled(!shown)
            .frame(height: shown ? allDayExpandedHeight : Tokens.hitTarget)
            .overlay {
                // Зоны сброса развёрнутой панели — по её видимой рамке, а не по содержимому прокрутки:
                // не вылезают на сетку и не оставляют мёртвых мест под короткими колонками.
                HStack(spacing: 0) {
                    ForEach(days, id: \.self) { day in
                        Color.clear.reportZone("allday-\(day)", enabled: live && shown && !pagerSwiping)
                    }
                }
                .allowsHitTesting(false)
            }
            .background(shown ? Tokens.panel.opacity(0.75) : Color.clear, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.white.opacity(shown ? 0.07 : 0), lineWidth: 1))
            .padding(.trailing, 8)
            .padding(.bottom, shown ? 6 : 0)
        }
        .onChange(of: shown) { _, value in
            // Свернули — содержимое снова с первой строки.
            if !value { allDayScroll.scrollTo(edge: .top) }
        }
    }

    private var allDayColumns: some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                let hovered = drag?.target == .allDay(day: day)
                let date = date(day)
                let list = allDay(column: index, day: day)
                let real = list.filter { $0.day == date }
                let shown = allDayPanelShown ? real : Array(real.prefix(1))
                let phantoms = list.filter { $0.day != date }
                // Свёрнуто: колонка 44 pt, фишка по центру, нажимается вся колонка. Развёрнуто: строки
                // через 4 pt, зона нажатия фишки захватывает половину зазора сверху и снизу.
                VStack(spacing: 0) {
                    ForEach(shown + phantoms, id: \.id) { task in
                        allDayChip(task, phantom: task.day != date)
                    }
                }
                .frame(maxWidth: .infinity,
                       minHeight: allDayPanelShown ? CGFloat(allDayMaxRows) * (allDayChipHeight + 4) : Tokens.hitTarget,
                       alignment: allDayPanelShown ? .top : .center)
                .padding(.horizontal, narrowColumns ? 1 : 3)
                .padding(.vertical, allDayPanelShown ? 4 : 0)
                .background(hovered ? Tokens.accent.opacity(0.14) : Color.clear)
                .overlay(alignment: .leading) { Rectangle().fill(Tokens.line).frame(width: 1) }
                .reportZone("allday-\(day)", enabled: live && !allDayPanelShown && !pagerSwiping)
            }
        }
    }

    /// Единственная кнопка строки без времени: свёрнуто — «+7» (сколько спрятано), развёрнуто —
    /// общее число на акцентной капсуле; тап переключает. Когда прятать нечего — пусто.
    /// Капсула стоит по центру первой фишки справа: свёрнуто — середина строки 44 pt, развёрнуто —
    /// середина первой строки панели.
    private var allDayBadge: some View {
        let total = allDayTotal
        let hidden = allDayHidden
        let expanded = allDayPanelShown
        let pill: CGFloat = 22
        let center = expanded ? 4 + 2 + allDayChipHeight / 2 : Tokens.hitTarget / 2
        return Button {
            withAnimation(.easeOut(duration: 0.2)) { allDayExpanded.toggle() }
        } label: {
            Text(expanded ? "\(total)" : "+\(hidden)")
                .font(.system(size: 11.5, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(expanded ? Tokens.onAccent : Tokens.caption)
                .frame(minWidth: 28, minHeight: pill)
                .padding(.horizontal, 3)
                .background(expanded ? Tokens.accent : Tokens.badge, in: Capsule())
                .opacity(hidden > 0 ? 1 : 0)
                .padding(.top, center - pill / 2)
                .frame(width: Tokens.gutter - 7, height: Tokens.hitTarget, alignment: .top)
                .padding(.trailing, 7)
                .contentShape(Rectangle())
        }
        .buttonStyle(.pageTap)
        .disabled(hidden == 0)
        .accessibilityLabel(expanded ? "Свернуть задачи без времени" : "Ещё \(hidden): показать все задачи без времени")
    }

    private func allDayChip(_ task: PlannerTask, phantom: Bool) -> some View {
        let style = task.style
        // Свёрнуто — вся строка 44 pt; развёрнуто — фишка плюс по 2 pt зазора сверху и снизу.
        let hitHeight = allDayPanelShown ? allDayChipHeight + 4 : Tokens.hitTarget
        return HStack(spacing: 2) {
            if !narrowColumns {
                Button { onToggle(task) } label: {
                    Circle()
                        .strokeBorder(style.dot, lineWidth: 2)
                        .background(Circle().fill(task.isDone ? style.dot : Color.clear))
                        .frame(width: 13, height: 13)
                        // Кружок нажимается на всю высоту строки, а не только внутри фишки.
                        .frame(width: 30, height: hitHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.pageTap)
                .accessibilityLabel((task.isDone ? "Вернуть в работу: " : "Отметить выполненной: ") + task.title)
            }
            Text(task.title)
                .font(.system(size: narrowColumns ? 11 : 12.5))
                .lineLimit(1)
                .strikethrough(task.isDone)
                .padding(.leading, narrowColumns ? 5 : 0)
            Spacer(minLength: 0)
        }
        .padding(.leading, 1)
        .padding(.trailing, compactColumns ? 4 : 8)
        .frame(height: allDayChipHeight)
        .foregroundStyle(style.text)
        .background(style.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(style.border, lineWidth: 1))
        // Невидимый фантом переноса не занимает места: строка не вырастает посреди переноса.
        .frame(height: phantom ? 0 : hitHeight)
        .opacity(phantom ? 0 : (drag?.taskID == task.id ? 0.35 : (task.isDone ? 0.55 : 1)))
        .contentShape(Rectangle())
        .onPageTap { onEdit(task) }
        .gesture(dragGesture(for: task))
    }

    // MARK: - Сетка

    private func grid(areaWidth: CGFloat) -> some View {
        let columnWidth = areaWidth / CGFloat(max(1, days.count))
        return ZStack(alignment: .topLeading) {
            // Колонки дней: свободное место каждой — зона создания и зона сброса.
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                let left = Tokens.gutter + columnWidth * CGFloat(index)
                columnBackground(day: day)
                    .frame(width: columnWidth, height: contentHeight)
                    .reportZone("grid-\(day)", space: "grid", enabled: live)
                    .position(x: left + columnWidth / 2, y: contentHeight / 2)
            }

            VStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { hour in
                    hourRow(hour)
                        .frame(height: Tokens.hourHeight, alignment: .top)
                }
            }
            .padding(.top, topInset)
            .padding(.bottom, bottomInset)
            .allowsHitTesting(false)

            ForEach(Array(days.enumerated()), id: \.offset) { index, _ in
                Rectangle()
                    .fill(Tokens.line)
                    .frame(width: 1, height: gridHeight)
                    .position(x: Tokens.gutter + columnWidth * CGFloat(index) + 0.5, y: topInset + gridHeight / 2)
                    .allowsHitTesting(false)
            }

            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                let left = Tokens.gutter + columnWidth * CGFloat(index)
                let date = date(day)
                let list = timed(column: index, day: day)
                let placed = placements(list, day: date)
                ForEach(list, id: \.id) { task in
                    let placement = placed[task.id.uuidString] ?? LanePlacement(id: task.id.uuidString, lane: 0, laneCount: 1)
                    block(task, placement: placement, columnLeft: left, columnWidth: columnWidth, phantom: task.day != date)
                        .zIndex(task.id == selectedID ? 2 : 1)
                }
                if drag == nil, let selected = list.first(where: { $0.id == selectedID && $0.day == date }),
                   let placement = placed[selected.id.uuidString] {
                    resizeHandle(selected, edge: .top, placement: placement, columnLeft: left, columnWidth: columnWidth)
                        .zIndex(4)
                    resizeHandle(selected, edge: .bottom, placement: placement, columnLeft: left, columnWidth: columnWidth)
                        .zIndex(4)
                }
            }

            if let drag = drag, case .grid(let day, let start) = drag.target, let index = days.firstIndex(of: day) {
                preview(start: start, duration: drag.duration, columnLeft: Tokens.gutter + columnWidth * CGFloat(index), columnWidth: columnWidth)
                    .zIndex(5)
            }

            if let creating = creating, let index = days.firstIndex(of: creating.day) {
                preview(start: creating.start, duration: creating.duration, columnLeft: Tokens.gutter + columnWidth * CGFloat(index), columnWidth: columnWidth)
                    .zIndex(5)
            }

            if let index = days.firstIndex(of: 0) {
                TimelineView(.everyMinute) { context in
                    let minutes = DayMath.nowMinutes(at: context.date)
                    let y = topInset + CGFloat(minutes) / 60 * Tokens.hourHeight
                    let nearestHourY = topInset + (CGFloat(minutes) / 60).rounded() * Tokens.hourHeight
                    ZStack(alignment: .topLeading) {
                        if abs(nearestHourY - y) < 22 {
                            // Подпись часа рядом с «сейчас» прячется, чтобы не налезать.
                            Rectangle()
                                .fill(Tokens.background)
                                .frame(width: Tokens.gutter - 8, height: 22)
                                .position(x: (Tokens.gutter - 8) / 2, y: nearestHourY)
                        }
                        nowLine(width: columnWidth)
                            .position(x: Tokens.gutter + columnWidth * CGFloat(index) + columnWidth / 2, y: y)
                        nowLabel(minutes: minutes)
                            .position(x: (Tokens.gutter - 8) / 2, y: y)
                    }
                }
                .allowsHitTesting(false)
                .zIndex(3)
            }
        }
        .frame(height: contentHeight)
        .coordinateSpace(name: "grid")
        .padding(.trailing, 8)
    }

    /// Свободное место колонки: тап снимает выделение, удержание создаёт задачу на 30 минут
    /// в этом месте, удержание с протягиванием вниз — задачу нужной длины (силуэт, пока тянешь).
    private func columnBackground(day: Int) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onPageTap {
                selectedID = nil
                liveDuration = nil
                liveStart = nil
            }
            .gesture(
                HoldDragGesture(space: "grid", onChanged: { location, start in
                    if creating == nil, !creationSuppressed, isOverBlock(day: day, y: start.y) {
                        creationSuppressed = true
                    }
                    guard !creationSuppressed else { return }
                    scroll.interacting = true
                    createTracker.day = day
                    createTracker.startY = start.y
                    createTracker.fingerY = location.y - scroll.offset + viewport.minY
                    updateCreating(day: day, startY: start.y, endY: location.y)
                    if abs(location.y - start.y) > 8 {
                        updateAutoScroll(fingerY: createTracker.fingerY)
                    }
                }, onEnded: {
                    scroll.interacting = false
                    stopAutoScroll()
                    if let creating = creating, !creationSuppressed {
                        onCreate(creating.day, creating.start, creating.duration)
                    }
                    creating = nil
                    createTracker.day = nil
                    creationSuppressed = false
                }, onCancelled: {
                    scroll.interacting = false
                    stopAutoScroll()
                    creating = nil
                    createTracker.day = nil
                    creationSuppressed = false
                })
            )
    }

    /// Силуэт создаваемой задачи от точки удержания до пальца (координаты содержимого сетки), шаг 15 минут;
    /// без протягивания вниз — 30 минут.
    private func updateCreating(day: Int, startY: CGFloat, endY: CGFloat) {
        let startMinutes = snappedMinutes(forY: startY)
        let end = snappedMinutes(forY: endY)
        let stretched = end > startMinutes ? min(end - startMinutes, ClockGrid.dayEnd - startMinutes) : 30
        let duration = max(15, stretched)
        let next = (day: day, start: ClockGrid.clampedStart(startMinutes, duration: duration), duration: duration)
        if creating?.day != next.day || creating?.start != next.start || creating?.duration != next.duration {
            creating = next
        }
    }

    private func block(_ task: PlannerTask, placement: LanePlacement, columnLeft: CGFloat, columnWidth: CGFloat, phantom: Bool) -> some View {
        let laneWidth = columnWidth / CGFloat(placement.laneCount)
        let width = max(0, laneWidth - 6)
        let start = start(of: task)
        let dur = min(duration(of: task), ClockGrid.dayEnd - start)
        let top = topInset + CGFloat(start) / 60 * Tokens.hourHeight + 1
        let height = max(CGFloat(dur) / 60 * Tokens.hourHeight - 2, 24)
        let selected = task.id == selectedID && drag == nil
        let left = columnLeft + laneWidth * CGFloat(placement.lane) + 3
        return TaskBlockView(
            task: task,
            height: height,
            compact: laneWidth < 160,
            narrow: laneWidth < 76,
            selected: selected,
            liveDuration: selected ? liveDuration : nil,
            liveStart: selected ? liveStart : nil,
            dimmed: drag?.taskID == task.id,
            onToggle: { onToggle(task) }
        )
        .frame(width: width, height: height)
        .opacity(phantom ? 0 : 1)
        .position(x: left + width / 2, y: top + height / 2)
        .onPageTap {
            if selectedID == task.id {
                onEdit(task)
            } else {
                selectedID = task.id
                liveDuration = nil
                liveStart = nil
            }
        }
        .gesture(dragGesture(for: task))
    }

    /// Ручка растягивания: нижняя двигает конец, верхняя — начало (конец на месте). Шаг 15 минут.
    /// Зона нажатия — см. `handleZone`; по ширине правее кружка-галочки и не шире своей колонки.
    /// Тап без движения внутри блока открывает редактор, снаружи — снимает выделение.
    private func resizeHandle(_ task: PlannerTask, edge: HandleEdge, placement: LanePlacement, columnLeft: CGFloat, columnWidth: CGFloat) -> some View {
        let laneWidth = columnWidth / CGFloat(placement.laneCount)
        let width = max(0, laneWidth - 6)
        let start = start(of: task)
        let top = topInset + CGFloat(start) / 60 * Tokens.hourHeight + 1
        let height = max(CGFloat(min(duration(of: task), ClockGrid.dayEnd - start)) / 60 * Tokens.hourHeight - 2, 24)
        let left = columnLeft + laneWidth * CGFloat(placement.lane) + 3
        let checkbox: CGFloat = laneWidth < 76 ? 0 : (laneWidth < 160 ? 26 : 34)
        let zoneWidth = min(88, max(min(24, laneWidth), width - checkbox))
        let zoneCenterX = left + checkbox + (width - checkbox) / 2
        let zone = handleZone(task, edge: edge, top: top, height: height)
        let outside = zone.outside
        let zoneHeight = zone.outside + zone.inside
        let edgeY = edge == .top ? top : top + height
        let zoneCenterY = edge == .top ? top - outside + zoneHeight / 2 : top + height + outside - zoneHeight / 2
        let originalStart = task.start ?? 0
        let originalEnd = originalStart + task.duration
        return Capsule()
            .fill(Color.white)
            // В узкой колонке недели капсула не шире самого блока и не ложится на соседний.
            .frame(width: min(44, max(16, width - 4)), height: 6)
            .overlay(Capsule().stroke(Tokens.background, lineWidth: 2))
            .offset(x: left + width / 2 - zoneCenterX, y: edgeY - zoneCenterY)
            .frame(width: zoneWidth, height: zoneHeight)
            .contentShape(Rectangle())
            .position(x: zoneCenterX, y: zoneCenterY)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("planner"))
                    .onChanged { value in
                        let moved = abs(value.translation.height) > 3 || abs(value.translation.width) > 3
                        guard moved else { return }
                        scroll.interacting = true
                        if resizeTracker.edge == nil {
                            resizeTracker.edge = edge
                            resizeTracker.originalStart = originalStart
                            resizeTracker.originalEnd = originalEnd
                            resizeTracker.grab = gridY(fromPlannerY: value.startLocation.y) - edgeY
                        }
                        resizeTracker.fingerY = value.location.y
                        applyResize(plannerY: value.location.y)
                        updateAutoScroll(fingerY: value.location.y)
                    }
                    .onEnded { value in
                        scroll.interacting = false
                        stopAutoScroll()
                        resizeTracker.edge = nil
                        let moved = abs(value.translation.height) > 3 || abs(value.translation.width) > 3
                        if !moved {
                            let y = gridY(fromPlannerY: value.startLocation.y)
                            if y >= top && y <= top + height {
                                onEdit(task)
                            } else {
                                selectedID = nil
                            }
                        } else if let newStart = liveStart, let newDuration = liveDuration,
                                  newStart != originalStart || newDuration != task.duration {
                            onRetime(task, newStart, newDuration)
                        } else if let newDuration = liveDuration, newDuration != task.duration {
                            onResize(task, newDuration)
                        }
                        liveDuration = nil
                        liveStart = nil
                    }
            )
            .accessibilityHidden(true)
    }

    /// Высота зоны ручки снаружи и внутри блока. Цель — 44 pt на каждую ручку:
    /// - у самой кромки внутри блока всегда есть своя часть (до 12 pt), чтобы схватить кромку;
    /// - остальное берётся снаружи, сколько свободно до соседнего блока;
    /// - не хватило — добирается внутрь, но середина блока (24 pt у блоков от 72 pt) остаётся для удержания
    ///   и переноса самого блока; две ручки делят внутренность по нужде, а не поровну;
    /// - если блок зажат соседями с обеих сторон и зона всё равно меньше 24 pt — заходит на соседа до 10 pt.
    private func handleZone(_ task: PlannerTask, edge: HandleEdge, top: CGFloat, height: CGFloat) -> (outside: CGFloat, inside: CGFloat) {
        let free = freeSpace(around: task, top: top, bottom: top + height)
        let gapTop = max(0, free.above - 1)
        let gapBottom = max(0, free.below - 1)
        let minIn = min(12, height / 4)
        let band: CGFloat = height >= 72 ? 24 : max(0, height - 48)
        let budget = max(2 * minIn, height - band)
        let outTop = min(Tokens.hitTarget - minIn, gapTop)
        let outBottom = min(Tokens.hitTarget - minIn, gapBottom)
        let needTop = max(minIn, Tokens.hitTarget - outTop)
        let needBottom = max(minIn, Tokens.hitTarget - outBottom)
        var inTop = needTop
        var inBottom = needBottom
        if inTop + inBottom > budget {
            let half = budget / 2
            if needTop <= half {
                inBottom = budget - needTop
            } else if needBottom <= half {
                inTop = budget - needBottom
            } else {
                inTop = half
                inBottom = half
            }
        }
        var outside = edge == .top ? outTop : outBottom
        let inside = edge == .top ? inTop : inBottom
        if outside + inside < 24 { outside += min(10, 24 - outside - inside) }
        return (outside, inside)
    }

    /// Сколько свободного места (pt) над блоком и под ним до ближайших блоков этого же дня, которые целиком
    /// выше или ниже. Блоки рядом в других дорожках (пересекаются по времени) не мешают: зона уже своей дорожки.
    private func freeSpace(around task: PlannerTask, top: CGFloat, bottom: CGFloat) -> (above: CGFloat, below: CGFloat) {
        var above = CGFloat.greatestFiniteMagnitude
        var below = CGFloat.greatestFiniteMagnitude
        for other in tasks where other.id != task.id && other.day == task.day {
            guard let otherStart = other.start else { continue }
            let otherTop = topInset + CGFloat(otherStart) / 60 * Tokens.hourHeight + 1
            let otherHeight = max(CGFloat(min(other.duration, ClockGrid.dayEnd - otherStart)) / 60 * Tokens.hourHeight - 2, 24)
            let otherBottom = otherTop + otherHeight
            if otherBottom <= top + 0.5 { above = min(above, top - otherBottom) }
            if otherTop >= bottom - 0.5 { below = min(below, otherTop - bottom) }
        }
        return (above, below)
    }

    /// Пересчитать начало или длительность по положению пальца (координаты «planner») с учётом захвата;
    /// вызывается и из жеста, и из цикла автопрокрутки, пока палец стоит у края.
    private func applyResize(plannerY: CGFloat) {
        guard let edge = resizeTracker.edge else { return }
        let y = gridY(fromPlannerY: plannerY) - resizeTracker.grab - topInset
        let minutes = Int((y / Tokens.hourHeight * 60 / 15).rounded()) * 15
        switch edge {
        case .bottom:
            let start = resizeTracker.originalStart
            let newDuration = max(15, min(minutes - start, ClockGrid.dayEnd - start))
            if newDuration != liveDuration { liveDuration = newDuration }
        case .top:
            let newStart = max(0, min(resizeTracker.originalEnd - 15, minutes))
            if newStart != liveStart {
                liveStart = newStart
                liveDuration = resizeTracker.originalEnd - newStart
            }
        }
    }

    private func dragGesture(for task: PlannerTask) -> some UIGestureRecognizerRepresentable {
        HoldDragGesture(
            onChanged: { location, start in onDragChanged(task, location, start) },
            onEnded: onDragEnded,
            onCancelled: onDragCancelled ?? onDragEnded
        )
    }

    private func preview(start: Int, duration: Int, columnLeft: CGFloat, columnWidth: CGFloat) -> some View {
        let height = max(CGFloat(duration) / 60 * Tokens.hourHeight - 2, 24)
        let top = topInset + CGFloat(start) / 60 * Tokens.hourHeight + 1
        let width = max(0, columnWidth - 6)
        return RoundedRectangle(cornerRadius: 9)
            .fill(Tokens.accent.opacity(0.14))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .foregroundStyle(Tokens.accent)
            )
            .overlay(alignment: .topLeading) {
                // В узкой колонке недели — только начало и почти без полей: «14:00» влезает целиком.
                Text(width < 90 ? ClockGrid.format(minutes: start) : ClockGrid.format(minutes: start) + "–" + ClockGrid.format(minutes: start + duration))
                    .font(.system(size: 12, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Tokens.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.92)
                    .padding(.horizontal, width < 90 ? 3 : 8)
                    .padding(.top, 3)
            }
            .frame(width: width, height: height)
            .position(x: columnLeft + 3 + width / 2, y: top + height / 2)
            .allowsHitTesting(false)
    }

    /// В этой точке колонки уже лежит блок с временем (с запасом 12 pt на ручки): удержание здесь —
    /// перенос или растягивание, создавать вторую задачу поверх нельзя.
    private func isOverBlock(day: Int, y: CGFloat) -> Bool {
        let date = date(day)
        let marginMinutes = 12 / Tokens.hourHeight * 60
        let minutes = (y - topInset) / Tokens.hourHeight * 60
        return tasks.contains { task in
            guard task.day == date, let start = task.start else { return false }
            let from = CGFloat(start) - marginMinutes
            let to = CGFloat(start + max(task.duration, 20)) + marginMinutes
            return minutes >= from && minutes <= to
        }
    }

    /// Минуты от 0:00 по вертикальной координате в сетке, с шагом 15 минут.
    private func snappedMinutes(forY y: CGFloat) -> Int {
        let minutes = Int(((y - topInset) / Tokens.hourHeight * 60 / 15).rounded(.down)) * 15
        return max(0, min(ClockGrid.dayEnd, minutes))
    }

    private func hourRow(_ hour: Int) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Tokens.line)
                .frame(height: 1)
                .padding(.leading, Tokens.gutter)
            Text("\(hour):00")
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(Tokens.muted)
                .frame(width: Tokens.gutter - 8, alignment: .trailing)
                .offset(y: -7)
        }
    }

    private func nowLine(width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(Tokens.accent).frame(height: 2)
            Circle().fill(Tokens.accent).frame(width: 10, height: 10).offset(x: -5)
        }
        .frame(width: width, height: 12)
    }

    /// Подпись текущего времени в левой колонке; фон закрывает подпись часа, если они совпали.
    private func nowLabel(minutes: Int) -> some View {
        Text(ClockGrid.format(minutes: minutes))
            .font(.system(size: 11, weight: .bold))
            .monospacedDigit()
            .foregroundStyle(Tokens.accent)
            .padding(.vertical, 2)
            .frame(width: Tokens.gutter - 8, alignment: .trailing)
            .background(Tokens.background)
    }
}
