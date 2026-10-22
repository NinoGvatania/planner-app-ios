import PlannerCore
import SwiftUI
import UIKit

/// Панель бэклога снизу. Три положения: свёрнута (только заголовок с счётчиком и «Просрочено» плюс
/// строка ввода — ничего не торчит), открыта (до 6 строк) и на весь экран. Тап по заголовку
/// открывает и сворачивает; свайп тянет за пальцем и отпускает к ближайшему положению.
/// Строки: тап — редактор, удержание — перенос, свайп влево — удалить.
/// Жест удержания висит на каждой строке: задачу знает сам жест, без поиска строки по рамкам
/// (рамки ячеек List устаревают — новая строка или сдвиг панели при закрытии клавиатуры, и перенос
/// не начинался). Чтобы строку не уничтожило, когда панель сворачивается в начале переноса,
/// список на время переноса сохраняет свою высоту и только обрезается панелью.
struct BacklogDrawerView: View {
    let tasks: [PlannerTask]
    @Binding var isOpen: Bool
    @Binding var input: String
    let onSubmit: () -> Void
    let onVoice: () -> Void
    let onToggle: (PlannerTask) -> Void
    let drag: DragState?
    let onDragChanged: (PlannerTask, CGPoint, CGPoint) -> Void
    let onDragEnded: () -> Void
    let onEdit: (PlannerTask) -> Void
    let onDelete: (PlannerTask) -> Void
    /// Сколько высоты экрана панель может занять (с клавиатурой — меньше).
    var maxHeight: CGFloat = .infinity
    var onDragCancelled: (() -> Void)? = nil
    /// «Просрочено · N» в заголовке панели; тап открывает лист просроченных.
    var overdueCount: Int = 0
    var onOverdue: (() -> Void)? = nil
    /// Фокус строки ввода: экран уступает место клавиатуре только ей.
    var inputFocus: FocusState<Bool>.Binding

    /// Смещение пальца во время свайпа по заголовку (вверх — отрицательное). Состояние жеста: если свайп
    /// оборвала система (звонок, Пункт управления), оно само возвращается к нулю пружиной, и панель
    /// не застревает на промежуточной высоте.
    @GestureState(resetTransaction: Transaction(animation: .spring(duration: 0.3)))
    private var dragDelta: CGFloat = 0
    /// Ширина панели — чтобы знать, какие названия займут две строки.
    @State private var drawerWidth: CGFloat = 0
    /// Панель раскрыта на весь экран.
    @State private var isFull = false
    /// Высота списка в момент, когда взяли задачу: пока её тянут, список не сжимается вместе с панелью,
    /// ячейка со строкой и её жестом остаётся жива.
    @State private var frozenListHeight: CGFloat?

    private let rowHeight: CGFloat = 66
    private var openCount: Int { tasks.filter { !$0.isDone }.count }
    private var collapsedHeight: CGFloat { Tokens.drawerCollapsed }
    /// Высота открытого списка — по настоящим строкам: название в две строки делает строку 84 pt, а не 66.
    /// Пустой список — одна строка «Пусто» (66) и поля.
    private var listHeight: CGFloat {
        tasks.isEmpty ? rowHeight + 8 : tasks.prefix(6).reduce(CGFloat(8)) { $0 + estimatedRowHeight($1) }
    }

    /// Строка `TaskRowView`: поля 8 + 8, отступ 10, название 16 pt (до двух строк), 4, вторая строка 13 pt.
    /// Название начинается через 40 pt от края строки (кружок 44 с заходом −10 и промежуток 6).
    private func estimatedRowHeight(_ task: PlannerTask) -> CGFloat {
        guard drawerWidth > 0 else { return rowHeight }
        let width = drawerWidth - 18 - 16 - 40
        let font = UIFont.systemFont(ofSize: 16)
        let bounds = (task.title as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        return bounds.height > font.lineHeight * 1.5 ? 84 : rowHeight
    }
    private var fullHeight: CGFloat { maxHeight.isFinite ? max(collapsedHeight + 100, maxHeight) : Tokens.drawerCollapsed + listHeight }
    private var openHeight: CGFloat { min(Tokens.drawerCollapsed + listHeight, fullHeight) }
    private var canExpand: Bool { fullHeight > openHeight + 60 }

    private var restHeight: CGFloat {
        guard isOpen else { return collapsedHeight }
        return isFull && canExpand ? fullHeight : openHeight
    }

    private var height: CGFloat {
        min(fullHeight, max(collapsedHeight, restHeight - dragDelta))
    }

    /// Видимая часть списка между заголовком и строкой ввода.
    private var visibleListHeight: CGFloat { max(0, height - Tokens.drawerCollapsed) }

    private var hint: String? {
        guard let drag = drag else { return nil }
        if drag.target == .backlog { return drag.fromTimeline ? "Отпусти — уберу сюда" : "Отпусти — оставлю здесь" }
        return drag.fromTimeline ? "Сюда — в бэклог" : "Тащи наверх"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            list
                .frame(height: frozenListHeight ?? visibleListHeight, alignment: .top)
                .frame(height: visibleListHeight, alignment: .top)
                .clipped()
            inputRow
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { drawerWidth = $0 }
        .reportZone("drawer")
        .background {
            // Жидкое стекло: панель слегка просвечивает сетку под собой.
            UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22)
                .fill(Color.clear)
                .glassEffect(
                    .regular.tint(drag?.target == .backlog ? Color(hex: 0x1B2A24) : Tokens.drawer.opacity(0.78)),
                    in: UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22)
                )
                .shadow(color: Color.black.opacity(0.45), radius: 15, y: -10)
                .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                .ignoresSafeArea(edges: .bottom)
        }
        .onChange(of: isOpen) { _, open in
            if !open { isFull = false }
        }
        .onChange(of: drag?.taskID) { _, id in
            // Перенос закончился где угодно (в том числе сбросом экрана) — список снова по высоте панели.
            if id == nil { frozenListHeight = nil }
        }
    }

    // MARK: - Заголовок

    private var header: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color(hex: 0x3A3B41))
                .frame(width: 38, height: 5)
                .padding(.top, 6)
                .padding(.bottom, 5)
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Text("Бэклог")
                        .font(.system(size: 17, weight: .bold))
                    Text("\(openCount)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xC9C9D1))
                        .frame(minWidth: 22, minHeight: 22)
                        .padding(.horizontal, 3)
                        .background(Tokens.badge, in: Capsule())
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Бэклог, \(openCount) " + DayMath.plural(openCount, "задача", "задачи", "задач"))
                .accessibilityHint(isOpen ? "Свернуть" : "Открыть")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { toggle() }
                Spacer(minLength: 8)
                if let hint = hint {
                    Text(hint)
                        .font(.system(size: 13))
                        .foregroundStyle(Tokens.accent)
                        .lineLimit(1)
                        .transition(.opacity)
                } else if overdueCount > 0, let onOverdue {
                    Button(action: onOverdue) {
                        HStack(spacing: 5) {
                            Image(systemName: "clock")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Просрочено")
                                .font(.system(size: 13, weight: .semibold))
                            Text("\(overdueCount)")
                                .font(.system(size: 12, weight: .bold))
                                .monospacedDigit()
                                .foregroundStyle(Color(hex: 0x1A0706))
                                .frame(minWidth: 20, minHeight: 20)
                                .padding(.horizontal, 2)
                                .background(Tokens.overdueBadge, in: Capsule())
                        }
                        .foregroundStyle(Tokens.overdue)
                        .padding(.leading, 10)
                        .padding(.trailing, 5)
                        .frame(height: 32)
                        .background(Tokens.overdueChip, in: Capsule())
                        .frame(height: Tokens.hitTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Просрочено: \(overdueCount)")
                    .transition(.opacity)
                }
            }
            .frame(height: Tokens.hitTarget)
            // Подсказка переноса и «Просрочено» сменяют друг друга плавно, без скачка.
            .animation(.easeOut(duration: 0.15), value: hint)
        }
        .padding(.horizontal, 18)
        .frame(height: Tokens.drawerHeader, alignment: .top)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .foregroundStyle(Tokens.text)
        .onTapGesture(perform: toggle)
        .gesture(
            DragGesture(minimumDistance: 10, coordinateSpace: .named("planner"))
                .updating($dragDelta) { value, state, _ in
                    state = value.translation.height
                }
                .onEnded { value in
                    let projected = restHeight - value.predictedEndTranslation.height
                    settle(to: projected)
                }
        )
        .accessibilityElement(children: .contain)
    }

    /// Тап по свёрнутой панели — открыть.
    private func open() {
        guard !isOpen else { return }
        withAnimation(.spring(duration: 0.3)) { isOpen = true }
    }

    /// Тап по заголовку: свёрнута → открыта, открыта → свёрнута, на весь экран → открыта.
    private func toggle() {
        withAnimation(.spring(duration: 0.3)) {
            if isFull && canExpand {
                isFull = false
            } else {
                isOpen.toggle()
            }
        }
    }

    /// Отпустили свайп: к ближайшему положению по тому, куда летел палец.
    private func settle(to projected: CGFloat) {
        var detents = [collapsedHeight, openHeight]
        if canExpand { detents.append(fullHeight) }
        let target = detents.min { abs($0 - projected) < abs($1 - projected) } ?? collapsedHeight
        withAnimation(.spring(duration: 0.3)) {
            isFull = canExpand && target == fullHeight
            isOpen = target > collapsedHeight
        }
    }

    // MARK: - Список

    private var list: some View {
        List {
            ForEach(tasks, id: \.id) { task in
                row(task)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 16))
                    .listRowSeparator(.hidden)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            onDelete(task)
                        } label: {
                            Label("Удалить", systemImage: "trash")
                        }
                    }
            }
            if tasks.isEmpty {
                Text("Пусто — всё разложено по дням.")
                    .font(.system(size: 14))
                    .foregroundStyle(Tokens.muted)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, rowHeight)
        .scrollDisabled(!isOpen)
    }

    private func row(_ task: PlannerTask) -> some View {
        TaskRowView(
            task: task,
            meta: task.isDone ? "сделано" : ClockGrid.formatDuration(task.duration),
            dimmed: drag?.taskID == task.id,
            onToggle: { onToggle(task) }
        )
        .contentShape(Rectangle())
        .onTapGesture { onEdit(task) }
        .gesture(
            HoldDragGesture(
                onChanged: { location, start in
                    // Первое срабатывание: запомнить высоту списка, пока панель ещё не начала сворачиваться.
                    if frozenListHeight == nil { frozenListHeight = visibleListHeight }
                    onDragChanged(task, location, start)
                },
                onEnded: {
                    onDragEnded()
                    frozenListHeight = nil
                },
                onCancelled: {
                    (onDragCancelled ?? onDragEnded)()
                    frozenListHeight = nil
                }
            )
        )
    }

    // MARK: - Ввод

    private var inputRow: some View {
        // Строка ввода и круглая кнопка — отдельные стеклянные фигуры (без контейнера: он склеивал бы их).
        HStack(alignment: .top, spacing: 10) {
            TextField("Завтра в 10 созвон, важно", text: $input)
                .focused(inputFocus)
                .font(.system(size: 15))
                .foregroundStyle(Tokens.text)
                .padding(.horizontal, 16)
                .frame(height: Tokens.hitTarget)
                .glassEffect(.regular.tint(Tokens.field.opacity(0.55)).interactive(), in: Capsule())
                .submitLabel(.done)
                .onSubmit(onSubmit)
                .accessibilityLabel("Новая задача")

            if input.trimmingCharacters(in: .whitespaces).isEmpty {
                Button(action: onVoice) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: Tokens.hitTarget, height: Tokens.hitTarget)
                        .glassEffect(.regular.tint(Tokens.accent.opacity(0.75)).interactive(), in: Circle())
                        .foregroundStyle(Tokens.onAccent)
                }
                .accessibilityLabel("Голосовой ввод")
            } else {
                Button(action: onSubmit) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: Tokens.hitTarget, height: Tokens.hitTarget)
                        .glassEffect(.regular.tint(Tokens.accent.opacity(0.75)).interactive(), in: Circle())
                        .foregroundStyle(Tokens.onAccent)
                }
                .accessibilityLabel("Добавить задачу")
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .frame(height: 60, alignment: .top)
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) }
    }
}
