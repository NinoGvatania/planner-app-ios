import PlannerCore
import SwiftUI

/// Панель бэклога снизу. Три положения: свёрнута (заголовок, две верхние задачи «торчат», строка ввода),
/// открыта (до 6 строк) и на весь экран. Тап по заголовку переключает, свайп тянет за пальцем и отпускает
/// к ближайшему положению. Строки: тап — редактор, удержание — перенос, свайп влево — удалить.
/// Жест удержания висит на контейнере списка, а не на строках: строка List может быть уничтожена,
/// когда панель сворачивается в начале переноса, и жест вместе с ней.
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
    /// Серия дней подряд (огонёк в заголовке) и что делать по тапу на неё.
    var streak: Int = 0
    var onStreak: (() -> Void)? = nil

    /// Смещение пальца во время свайпа по заголовку (вверх — отрицательное).
    @State private var dragDelta: CGFloat = 0
    /// Панель раскрыта на весь экран.
    @State private var isFull = false
    /// Рамки строк в координатах «planner» — чтобы понять, какую задачу взяли удержанием.
    @State private var rowFrames: [UUID: CGRect] = [:]
    @State private var draggingTask: PlannerTask?

    private let rowHeight: CGFloat = 50
    private var openCount: Int { tasks.filter { !$0.isDone }.count }
    /// Сколько строк «торчит» в свёрнутом виде.
    private var peekRows: Int { min(tasks.count, 2) }
    private var peekHeight: CGFloat { peekRows == 0 ? 0 : CGFloat(peekRows) * rowHeight + 4 }
    private var collapsedHeight: CGFloat { Tokens.drawerCollapsed + peekHeight }
    private var listHeight: CGFloat { tasks.isEmpty ? 48 : CGFloat(min(tasks.count, 6)) * rowHeight + 8 }
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

    private var hint: String? {
        guard let drag = drag else { return nil }
        if drag.target == .backlog { return drag.fromTimeline ? "Отпусти — уберу сюда" : "Отпусти — оставлю здесь" }
        return drag.fromTimeline ? "Сюда — в бэклог" : "Тащи наверх"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            list
                .frame(height: max(0, height - Tokens.drawerCollapsed), alignment: .top)
                .clipped()
                .contentShape(Rectangle())
                .onPreferenceChange(BacklogRowFramesKey.self) { rowFrames = $0 }
                .gesture(
                    HoldDragGesture(
                        onChanged: { location, start in
                            if draggingTask == nil {
                                guard let task = tasks.first(where: { rowFrames[$0.id]?.contains(start) == true }) else { return }
                                draggingTask = task
                            }
                            if let task = draggingTask {
                                onDragChanged(task, location, start)
                            }
                        },
                        onEnded: {
                            if draggingTask != nil { onDragEnded() }
                            draggingTask = nil
                        },
                        onCancelled: {
                            if draggingTask != nil { (onDragCancelled ?? onDragEnded)() }
                            draggingTask = nil
                        }
                    )
                )
            inputRow
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .reportZone("drawer")
        .background {
            UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22)
                .fill(drag?.target == .backlog ? Color(hex: 0x1B2A24) : Tokens.drawer)
                .shadow(color: Color.black.opacity(0.45), radius: 15, y: -10)
                .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                .ignoresSafeArea(edges: .bottom)
        }
        .animation(.spring(duration: 0.3), value: tasks.count)
        .onChange(of: isOpen) { _, open in
            if !open { isFull = false }
        }
    }

    // MARK: - Заголовок

    private var header: some View {
        VStack(spacing: 8) {
            Capsule()
                .fill(Color(hex: 0x3A3B41))
                .frame(width: 38, height: 5)
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
                    if let onStreak {
                        Button(action: onStreak) {
                            HStack(spacing: 3) {
                                Image(systemName: streak > 0 ? "flame.fill" : "flame")
                                    .font(.system(size: 13, weight: .bold))
                                Text("\(streak)")
                                    .font(.system(size: 13, weight: .bold))
                                    .monospacedDigit()
                            }
                            .foregroundStyle(streak > 0 ? Color(hex: 0xFF9F43) : Tokens.muted)
                            .padding(.horizontal, 8)
                            .frame(height: 26)
                            .background(Tokens.badge, in: Capsule())
                            .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Серия: \(streak) дней подряд")
                    }
                }
                Spacer()
                if let hint = hint {
                    Text(hint)
                        .font(.system(size: 13))
                        .foregroundStyle(Tokens.accent)
                } else if isOpen {
                    Button("Готово") {
                        withAnimation(.spring(duration: 0.3)) {
                            isFull = false
                            isOpen = false
                        }
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Tokens.accent)
                    .frame(minWidth: Tokens.hitTarget, minHeight: 36)
                    .accessibilityLabel("Свернуть бэклог")
                } else {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Tokens.caption)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                        .frame(width: 30, height: 30)
                        .background(Tokens.badge, in: Circle())
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 7)
        .frame(height: 52, alignment: .top)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .foregroundStyle(Tokens.text)
        .onTapGesture(perform: toggle)
        .gesture(
            DragGesture(minimumDistance: 10, coordinateSpace: .named("planner"))
                .onChanged { value in
                    dragDelta = value.translation.height
                }
                .onEnded { value in
                    let projected = restHeight - value.predictedEndTranslation.height
                    settle(to: projected)
                }
        )
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(isOpen ? "Свернуть бэклог" : "Открыть бэклог")
    }

    /// Тап: свёрнута → открыта, открыта → свёрнута, на весь экран → открыта.
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
            dragDelta = 0
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
                    .listRowInsets(EdgeInsets(top: 0, leading: 10, bottom: 0, trailing: 10))
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
        let style = task.style
        return HStack(spacing: 4) {
            Button { onToggle(task) } label: {
                Circle()
                    .strokeBorder(style.dot, lineWidth: 2)
                    .background(Circle().fill(task.isDone ? style.dot : Color.clear))
                    .frame(width: 20, height: 20)
                    .frame(width: Tokens.hitTarget, height: Tokens.hitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel((task.isDone ? "Вернуть в работу: " : "Отметить выполненной: ") + task.title)
            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.system(size: 15))
                    .lineLimit(1)
                    .strikethrough(task.isDone)
                Text(task.isDone ? "сделано" : ClockGrid.formatDuration(task.duration) + (task.project.map { " · \($0.name)" } ?? ""))
                    .font(.system(size: 12))
                    .foregroundStyle(Tokens.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 14))
                .foregroundStyle(Color(hex: 0x5A5B63))
                .padding(.trailing, 4)
        }
        .frame(height: rowHeight)
        .opacity(drag?.taskID == task.id ? 0.35 : (task.isDone ? 0.5 : 1))
        .foregroundStyle(Tokens.text)
        .contentShape(Rectangle())
        .onTapGesture { onEdit(task) }
        .background(
            GeometryReader { geometry in
                Color.clear.preference(key: BacklogRowFramesKey.self, value: [task.id: geometry.frame(in: .named("planner"))])
            }
        )
    }

    // MARK: - Ввод

    private var inputRow: some View {
        HStack(alignment: .top, spacing: 8) {
            TextField("Завтра в 10 созвон, важно", text: $input)
                .font(.system(size: 15))
                .foregroundStyle(Tokens.text)
                .padding(.horizontal, 16)
                .frame(height: Tokens.hitTarget)
                .background(Tokens.field, in: Capsule())
                .submitLabel(.done)
                .onSubmit(onSubmit)
                .accessibilityLabel("Новая задача")

            if input.trimmingCharacters(in: .whitespaces).isEmpty {
                Button(action: onVoice) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .frame(width: Tokens.hitTarget, height: Tokens.hitTarget)
                        .glassEffect(.regular.tint(Tokens.accent).interactive(), in: Circle())
                        .foregroundStyle(Tokens.onAccent)
                }
                .accessibilityLabel("Голосовой ввод")
            } else {
                Button(action: onSubmit) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: Tokens.hitTarget, height: Tokens.hitTarget)
                        .glassEffect(.regular.tint(Tokens.accent).interactive(), in: Circle())
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

/// Рамки строк бэклога в координатах «planner»; живут внутри панели и не трогают экран.
struct BacklogRowFramesKey: PreferenceKey {
    static var defaultValue: [UUID: CGRect] { [:] }
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}
