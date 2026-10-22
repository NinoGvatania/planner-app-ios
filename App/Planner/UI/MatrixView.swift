import PlannerCore
import SwiftUI

/// Матрица Эйзенхауэра. «Матрица» — 2×2 квадранта и полка «Не разобрано», всё целиком на экране:
/// в клетке столько задач, сколько влезает, остальное — «+N»; тап по клетке проваливается в полный
/// список квадранта. «Список» — секции по убыванию приоритета, каждую можно свернуть.
/// Пока задачу держат, поверх всего появляется доска из пяти цветных контейнеров — бросать можно куда угодно.
struct MatrixView: View {
    let tasks: [PlannerTask]
    let drag: DragState?
    let onToggle: (PlannerTask) -> Void
    let onDragChanged: (PlannerTask, CGPoint, CGPoint) -> Void
    let onDragEnded: () -> Void
    let onEdit: (PlannerTask) -> Void
    var onDelete: ((PlannerTask) -> Void)? = nil
    var onDragCancelled: (() -> Void)? = nil
    /// Средняя страница пейджера: только она сообщает зоны сброса.
    var live = true
    /// Пока открыт список квадранта (свайпы строк), экран не листается.
    var lock: PagingLock? = nil

    @AppStorage("matrixLayout") private var layoutRaw = "grid"
    /// Открытый на весь экран квадрант: 1…4 — квадрант, 0 — «Не разобрано».
    @State private var expanded: Int?
    /// Свёрнутые секции режима «Список».
    @State private var collapsed: Set<Int> = []

    private let labelWidth: CGFloat = 18
    private let cellSpacing: CGFloat = 8
    private let rowHeight: CGFloat = Tokens.hitTarget
    private let cellHeaderHeight: CGFloat = 34
    /// Полка «Не разобрано» в сетке: шапка и две строки задач (или «+N ещё»).
    private var trayHeight: CGFloat { cellHeaderHeight + 2 * (rowHeight + 3) + 10 }
    private var isList: Bool { layoutRaw == "list" }

    // MARK: - Данные

    private func items(for raw: Int) -> [PlannerTask] {
        raw == 0 ? unsortedTasks : items(for: Quadrant(rawValue: raw) ?? .other)
    }

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

    private var unsortedTasks: [PlannerTask] {
        tasks
            .filter { !$0.isDone && !$0.isRoutine && !$0.isSorted }
            .sorted { a, b in
                if (a.day == nil) != (b.day == nil) { return a.day != nil }
                if let da = a.day, let db = b.day, da != db { return da < db }
                return a.backlogRank > b.backlogRank
            }
    }

    private func cellStyle(_ raw: Int) -> QuadrantStyle {
        Quadrant(rawValue: raw)?.style ?? .unsorted
    }

    private func cellName(_ raw: Int) -> String {
        Quadrant(rawValue: raw)?.name ?? "Не разобрано"
    }

    // MARK: - Тело

    var body: some View {
        ZStack {
            // Переход «толчком»: список квадранта въезжает справа на непрозрачном фоне, сетка уезжает влево —
            // два слоя текста не накладываются.
            if let raw = expanded {
                detail(raw)
                    .transition(.move(edge: .trailing))
            } else {
                overview
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            if drag != nil {
                dropBoard
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: drag != nil)
        .animation(.easeInOut(duration: 0.22), value: expanded)
        .onChange(of: expanded) { _, value in
            if live { lock?.locked = value != nil }
        }
        .onDisappear {
            if live { lock?.locked = false }
        }
    }

    private var overview: some View {
        VStack(spacing: 0) {
            Picker("Вид матрицы", selection: $layoutRaw) {
                Text("Матрица").tag("grid")
                Text("Список").tag("list")
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
            if isList {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 10) {
                        ForEach(Quadrant.allCases, id: \.rawValue) { quadrant in
                            section(raw: quadrant.rawValue)
                        }
                        section(raw: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 16)
                }
            } else {
                GeometryReader { geometry in
                    gridLayout(height: geometry.size.height)
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
        }
    }

    // MARK: - Матрица 2×2 на весь экран

    /// Клетки делят всю высоту. Если места мало (открыт бэклог, клавиатура), сначала убирается полка
    /// «Не разобрано» (её задачи видны в списке и в доске при переносе), потом клетки сжимаются до шапки
    /// со счётчиком, а если не влезают и шапки — вместо сетки одна строка капсул «точка + число».
    /// Ничего не обрезается посередине строки.
    @ViewBuilder
    private func gridLayout(height: CGFloat) -> some View {
        let axisHeight: CGFloat = 22
        // Клетка с одной строкой: шапка, 3 + 44 на строку, 3 до распорки и 5 снизу (как в `cell`).
        let minCell = cellHeaderHeight + 8 + (rowHeight + 3)
        let withTray = (height - axisHeight - trayHeight - cellSpacing * 3) / 2
        let showTray = withTray >= minCell
        let cellHeight = showTray ? withTray : (height - axisHeight - cellSpacing * 2) / 2
        // Повёрнутая подпись «НЕ ВАЖНО» длиной около 64 pt: в более низкой клетке подписи налезли бы друг на друга.
        let rowLabelsShown = cellHeight >= 70
        if height < Tokens.hitTarget {
            // Даже строка капсул не влезает (пейджер такую страницу и так прячет) — ничего не резать.
            Color.clear
        } else if cellHeight < cellHeaderHeight {
            compactStrip
        } else {
            VStack(spacing: cellSpacing) {
                HStack(spacing: cellSpacing) {
                    Color.clear.frame(width: labelWidth, height: axisHeight)
                    axisLabel("Срочно")
                    axisLabel("Не срочно")
                }
                .frame(height: axisHeight)
                HStack(spacing: cellSpacing) {
                    rowLabel("Важно")
                        .opacity(rowLabelsShown ? 1 : 0)
                    cell(.urgentImportant, height: cellHeight)
                    cell(.important, height: cellHeight)
                }
                .frame(height: cellHeight)
                HStack(spacing: cellSpacing) {
                    rowLabel("Не важно")
                        .opacity(rowLabelsShown ? 1 : 0)
                    cell(.urgent, height: cellHeight)
                    cell(.other, height: cellHeight)
                }
                .frame(height: cellHeight)
                if showTray {
                    unsortedTray
                        .padding(.leading, labelWidth + cellSpacing)
                }
            }
            .frame(height: height, alignment: .top)
            .clipped()
        }
    }

    /// Совсем мало места: четыре квадранта и «Не разобрано» капсулами 44 pt с числом задач, тап — список.
    private var compactStrip: some View {
        HStack(spacing: 6) {
            ForEach([1, 2, 3, 4, 0], id: \.self) { raw in
                let style = cellStyle(raw)
                let count = items(for: raw).count
                Button {
                    expanded = raw
                } label: {
                    HStack(spacing: 5) {
                        Circle().fill(style.dot).frame(width: 10, height: 10)
                        Text("\(count)")
                            .font(.system(size: 13, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(style.text)
                    }
                    .frame(maxWidth: .infinity, minHeight: Tokens.hitTarget)
                    .background(style.background, in: Capsule())
                    .overlay(Capsule().strokeBorder(style.border, lineWidth: 1.5))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(cellName(raw) + ", \(count)")
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
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

    /// Клетка фиксированной высоты: заголовок, сколько влезает задач, «+N ещё» вместо последней.
    private func cell(_ quadrant: Quadrant, height: CGFloat) -> some View {
        let style = quadrant.style
        let list = items(for: quadrant)
        // Строк влезает 0, если клетка сжата до шапки: тогда видно только число в шапке.
        let slots = max(0, Int((height - cellHeaderHeight - 8) / (rowHeight + 3)))
        let visible: [PlannerTask] = slots == 0 ? [] : (list.count > slots ? Array(list.prefix(slots - 1)) : list)
        let hidden = slots == 0 ? 0 : list.count - visible.count
        return VStack(spacing: 3) {
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
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(style.text.opacity(0.6))
            }
            .padding(.horizontal, 10)
            .frame(height: cellHeaderHeight)
            ForEach(visible, id: \.id) { task in
                compactRow(task, style: style)
            }
            if hidden > 0 {
                Button {
                    expanded = quadrant.rawValue
                } label: {
                    Text("+\(hidden) ещё")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(style.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: rowHeight)
                        .background(Color.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Показать все: " + quadrant.name)
            }
            if list.isEmpty, slots > 0 {
                Text("Пусто — перетащи сюда")
                    .font(.system(size: 12.5))
                    .foregroundStyle(style.text.opacity(0.75))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 5)
        .padding(.bottom, slots > 0 ? 5 : 0)
        .frame(maxWidth: .infinity)
        .frame(height: height, alignment: .top)
        .clipped()
        .background(style.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(style.border, lineWidth: 1.5))
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture { expanded = quadrant.rawValue }
        .accessibilityLabel(quadrant.name)
        .accessibilityAddTraits(.isButton)
    }

    /// Строка в клетке: одна строка названия, под ней когда. Высота фиксированная — ничего не растягивается.
    private func compactRow(_ task: PlannerTask, style: QuadrantStyle) -> some View {
        let today = DayMath.today()
        let overdue = task.isOverdue(today: today)
        return HStack(spacing: 0) {
            Button { onToggle(task) } label: {
                Circle()
                    .strokeBorder(task.style.dot, lineWidth: 2)
                    .frame(width: 16, height: 16)
                    .frame(width: Tokens.hitTarget, height: rowHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Отметить выполненной: " + task.title)
            VStack(alignment: .leading, spacing: 1) {
                Text(task.title)
                    .font(.system(size: 13))
                    .foregroundStyle(style.text)
                    .lineLimit(1)
                Text(meta(task))
                    .font(.system(size: 11))
                    .foregroundStyle(overdue ? Tokens.overdue : Tokens.caption)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.trailing, 6)
        .frame(height: rowHeight)
        .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 10))
        .opacity(drag?.taskID == task.id ? 0.35 : 1)
        .contentShape(Rectangle())
        .onTapGesture { onEdit(task) }
        .gesture(HoldDragGesture(onChanged: { location, start in onDragChanged(task, location, start) }, onEnded: onDragEnded, onCancelled: onDragCancelled ?? onDragEnded))
    }

    // MARK: - Список по приоритету (секции сворачиваются)

    /// Секция списка: квадрант (1…4) или «Не разобрано» (0) — один и тот же вид строк.
    private func section(raw: Int) -> some View {
        let style = cellStyle(raw)
        let list = items(for: raw)
        let isCollapsed = collapsed.contains(raw)
        let label = Quadrant(rawValue: raw)?.label.lowercased() ?? "перетащи в квадрант"
        return VStack(spacing: 2) {
            Button {
                withAnimation(.spring(duration: 0.28)) {
                    if isCollapsed { collapsed.remove(raw) } else { collapsed.insert(raw) }
                }
            } label: {
                HStack(spacing: 8) {
                    Circle().fill(style.dot).frame(width: 10, height: 10)
                    Text(cellName(raw))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(style.text)
                    Text("· " + label)
                        .font(.system(size: 13))
                        .foregroundStyle(style.text.opacity(0.7))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Text("\(list.count)")
                        .font(.system(size: 13, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(style.dot)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(style.text.opacity(0.6))
                        .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                }
                .padding(.horizontal, 12)
                .frame(height: Tokens.hitTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel((isCollapsed ? "Развернуть: " : "Свернуть: ") + cellName(raw))
            if !isCollapsed {
                ForEach(list, id: \.id) { task in
                    wideRow(task, style: style)
                }
                if list.isEmpty {
                    Text(raw == 0 ? "Всё разобрано" : "Пусто — перетащи сюда")
                        .font(.system(size: 13))
                        .foregroundStyle(style.text.opacity(0.75))
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

    private func wideRow(_ task: PlannerTask, style: QuadrantStyle) -> some View {
        let today = DayMath.today()
        let overdue = task.isOverdue(today: today)
        return HStack(spacing: 2) {
            Button { onToggle(task) } label: {
                Circle()
                    .strokeBorder(task.style.dot, lineWidth: 2)
                    .frame(width: 20, height: 20)
                    .frame(width: Tokens.hitTarget, height: Tokens.hitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Отметить выполненной: " + task.title)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.system(size: 15))
                    .foregroundStyle(Tokens.text)
                    .lineLimit(2)
                Text(meta(task) + (task.project.map { " · " + $0.name } ?? ""))
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
        .opacity(drag?.taskID == task.id ? 0.35 : 1)
        .contentShape(Rectangle())
        .onTapGesture { onEdit(task) }
        .gesture(HoldDragGesture(onChanged: { location, start in onDragChanged(task, location, start) }, onEnded: onDragEnded, onCancelled: onDragCancelled ?? onDragEnded))
    }

    private func meta(_ task: PlannerTask) -> String {
        if let day = task.day {
            let label = DayMath.label(offset: DayMath.offset(of: day))
            return task.start.map { label + " " + ClockGrid.format(minutes: $0) } ?? label
        }
        return "бэклог"
    }

    // MARK: - Не разобрано

    /// Полка серых задач без квадранта в сетке: шапка как у клеток и такие же строки, как в клетках.
    /// Две строки видно сразу, остальное — «+N ещё»; тап по любому месту полки (кроме строк) — весь список.
    private var unsortedTray: some View {
        let list = unsortedTasks
        let style = QuadrantStyle.unsorted
        let visible = list.count > 2 ? Array(list.prefix(1)) : list
        let hidden = list.count - visible.count
        return VStack(spacing: 3) {
            HStack(spacing: 6) {
                Circle().fill(style.dot).frame(width: 10, height: 10)
                Text("Не разобрано")
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(style.text)
                Spacer(minLength: 0)
                Text("\(list.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Tokens.caption)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(style.text.opacity(0.6))
            }
            .padding(.horizontal, 10)
            .frame(height: cellHeaderHeight)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Не разобрано, \(list.count) — показать все")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { expanded = 0 }
            ForEach(visible, id: \.id) { task in
                compactRow(task, style: style)
            }
            if hidden > 0 {
                Button {
                    expanded = 0
                } label: {
                    Text("+\(hidden) ещё")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(style.text)
                        .frame(maxWidth: .infinity)
                        .frame(height: rowHeight)
                        .background(Color.black.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ещё \(hidden): показать все неразобранные")
            }
            if list.isEmpty {
                Text("Всё разобрано")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Tokens.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 5)
        .padding(.bottom, 5)
        .frame(height: trayHeight)
        .frame(maxWidth: .infinity)
        .clipped()
        .background(style.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(style.border, lineWidth: 1.5))
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onTapGesture { expanded = 0 }
    }

    // MARK: - Полный список квадранта

    private func detail(_ raw: Int) -> some View {
        let style = cellStyle(raw)
        let list = items(for: raw)
        return VStack(spacing: 0) {
            HStack(spacing: 6) {
                Button {
                    expanded = nil
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Tokens.text)
                        .frame(width: Tokens.hitTarget, height: Tokens.hitTarget)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Назад к матрице")
                Circle().fill(style.dot).frame(width: 10, height: 10)
                VStack(alignment: .leading, spacing: 0) {
                    Text(cellName(raw))
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Tokens.text)
                    if let quadrant = Quadrant(rawValue: raw) {
                        Text(quadrant.label)
                            .font(.system(size: 12))
                            .foregroundStyle(Tokens.caption)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(list.count)")
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(style.dot)
                    .padding(.trailing, 14)
            }
            .frame(height: 52)
            .padding(.leading, 4)
            List {
                ForEach(list, id: \.id) { task in
                    wideRow(task, style: style)
                        .listRowInsets(EdgeInsets(top: 3, leading: 10, bottom: 3, trailing: 10))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if let onDelete {
                                Button(role: .destructive) { onDelete(task) } label: {
                                    Label("Удалить", systemImage: "trash")
                                }
                            }
                        }
                }
                if list.isEmpty {
                    Text(raw == 0 ? "Всё разобрано" : "Пусто — перетащи сюда задачу, удерживая её")
                        .font(.system(size: 14))
                        .foregroundStyle(Tokens.caption)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 30)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .background(style.background.opacity(0.45))
        .background(Tokens.background)
    }

    // MARK: - Доска для сброса

    /// Пять контейнеров-целей на весь экран: пока задачу держат, бросить можно в любой.
    private var dropBoard: some View {
        VStack(spacing: 10) {
            Text("Куда?")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Tokens.caption)
                .frame(height: 24)
            HStack(spacing: 10) {
                boardCell(.urgentImportant)
                boardCell(.important)
            }
            HStack(spacing: 10) {
                boardCell(.urgent)
                boardCell(.other)
            }
            boardTarget(raw: 0, title: "Не разобрано", subtitle: "разберу позже", style: .unsorted)
                .frame(height: 76)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tokens.background.opacity(0.94))
        .allowsHitTesting(false)
    }

    private func boardCell(_ quadrant: Quadrant) -> some View {
        boardTarget(raw: quadrant.rawValue, title: quadrant.name, subtitle: quadrant.label, style: quadrant.style)
    }

    private func boardTarget(raw: Int, title: String, subtitle: String, style: QuadrantStyle) -> some View {
        let hovered = drag?.target == .quadrant(raw)
        let count = items(for: raw).count
        return VStack(spacing: 6) {
            Circle().fill(style.dot).frame(width: 14, height: 14)
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(style.text)
                .multilineTextAlignment(.center)
            Text(subtitle + " · \(count)")
                .font(.system(size: 12))
                .foregroundStyle(style.text.opacity(0.7))
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Фон ровно по форме рамки (стекло рисовало подложку шире рамки).
        .background(hovered ? Tokens.accent.opacity(0.22) : style.background, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(hovered ? Tokens.accent : style.border, lineWidth: hovered ? 2.5 : 1.5))
        .scaleEffect(hovered ? 1.02 : 1)
        .animation(.easeOut(duration: 0.12), value: hovered)
        .reportZone("quad-\(raw)", enabled: live && drag != nil)
    }
}
