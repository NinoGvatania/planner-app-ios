import PlannerCore
import SwiftUI
import UIKit

/// Нижний «остров» как поле ввода в Claude: висит над календарём, полупрозрачный, опущен к краю экрана.
/// Две строки: сверху «Бэклог · N» и «Просрочено · N», снизу строка ввода с микрофоном. Тап по строке
/// бэклога (или свайп вверх) раскрывает остров на всю ширину и не выше половины экрана — календарь под ним
/// не сжимается. Строка бэклога всегда на месте: на неё бросают задачи, чтобы убрать их в бэклог.
/// Строки: тап — редактор, удержание — перенос, свайп влево — удалить.
/// Жест удержания висит на каждой строке: задачу знает сам жест, без поиска строки по рамкам
/// (рамки ячеек List устаревают — новая строка или сдвиг панели при закрытии клавиатуры, и перенос
/// не начинался). Чтобы строку не уничтожило, когда остров сворачивается в начале переноса,
/// список на время переноса сохраняет свою высоту и только обрезается островом.
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
    /// Сколько высоты остров может занять, без отступа снизу (половина экрана, с клавиатурой — меньше).
    var maxHeight: CGFloat = .infinity
    /// Отступ под строкой ввода у раскрытого острова (он доходит до края экрана) — над полоской «домой».
    var bottomPadding: CGFloat = 0
    /// Зазор под свёрнутым островом до края экрана.
    var floatingGap: CGFloat = 0
    var onDragCancelled: (() -> Void)? = nil
    /// «Просрочено · N» в строке бэклога; тап открывает лист просроченных.
    var overdueCount: Int = 0
    var onOverdue: (() -> Void)? = nil
    /// Фокус строки ввода: экран уступает место клавиатуре только ей.
    var inputFocus: FocusState<Bool>.Binding

    /// Смещение пальца во время свайпа по строке бэклога (вверх — отрицательное). Состояние жеста: если свайп
    /// оборвала система (звонок, Пункт управления), оно само возвращается к нулю пружиной, и остров
    /// не застревает на промежуточной высоте.
    @GestureState(resetTransaction: Transaction(animation: .spring(duration: 0.3)))
    private var dragDelta: CGFloat = 0
    /// Ширина острова — чтобы знать, какие названия займут две строки.
    @State private var drawerWidth: CGFloat = 0
    /// Высота списка в момент, когда взяли задачу: пока её тянут, список не сжимается вместе с островом,
    /// ячейка со строкой и её жестом остаётся жива.
    @State private var frozenListHeight: CGFloat?
    /// Начало экрана в координатах окна — палец при переносе считается по UIKit, а не по устаревающей
    /// геометрии ячейки List.
    @State private var plannerOrigin = PlannerOrigin()

    private let rowHeight: CGFloat = 66
    private var openCount: Int { tasks.filter { !$0.isDone }.count }
    private var collapsedHeight: CGFloat { Tokens.islandHeader + Tokens.islandInput }
    /// Высота открытого списка — по настоящим строкам: название в две строки делает строку 84 pt, а не 66.
    /// Пустой список — одна строка «Пусто» (66) и поля.
    private var listHeight: CGFloat {
        tasks.isEmpty ? rowHeight + 8 : tasks.reduce(CGFloat(8)) { $0 + estimatedRowHeight($1) }
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
    /// Раскрытый остров: по строкам, но не выше `maxHeight` и не ниже одной строки списка.
    private var openHeight: CGFloat {
        let limit = maxHeight.isFinite ? max(collapsedHeight + rowHeight + 8, maxHeight) : .infinity
        return min(collapsedHeight + listHeight, limit)
    }

    private var restHeight: CGFloat { isOpen ? openHeight : collapsedHeight }

    private var height: CGFloat {
        min(openHeight, max(collapsedHeight, restHeight - dragDelta))
    }

    /// Остров раскрыт или раскрывается: тогда он во всю ширину и до края экрана.
    private var expanded: Bool { isOpen || height > collapsedHeight + 1 }

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 26, bottomLeadingRadius: expanded ? 0 : 26,
                               bottomTrailingRadius: expanded ? 0 : 26, topTrailingRadius: 26, style: .continuous)
    }

    /// Список снова по высоте острова — той же пружиной, что сворачивает остров: если отпустили сразу,
    /// пока он ещё едет вниз, строки уходят вместе с ним, а не исчезают рывком.
    private func releaseList() {
        guard frozenListHeight != nil else { return }
        withAnimation(.spring(duration: 0.3)) { frozenListHeight = nil }
    }

    /// Видимая часть списка между строкой бэклога и строкой ввода.
    private var visibleListHeight: CGFloat { max(0, height - collapsedHeight) }

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
        .padding(.bottom, expanded ? bottomPadding : 0)
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { drawerWidth = $0 }
        .trackPlannerOrigin(plannerOrigin)
        .background {
            // Жидкое стекло: остров просвечивает календарь под собой.
            shape
                .fill(Color.clear)
                .glassEffect(
                    .regular.tint(drag?.target == .backlog ? Color(hex: 0x1B2A24) : Tokens.drawer.opacity(0.6)),
                    in: shape
                )
                .shadow(color: Color.black.opacity(0.35), radius: 14, y: 4)
        }
        .overlay { shape.strokeBorder(Color.white.opacity(0.07), lineWidth: 1) }
        // Зона сброса — сам остров: строка бэклога всегда на месте, туда тащат задачи.
        .reportZone("drawer")
        .padding(.horizontal, expanded ? 0 : 10)
        .padding(.bottom, expanded ? 0 : floatingGap)
        .onChange(of: drag?.taskID) { _, id in
            // Перенос закончился где угодно (в том числе сбросом экрана) — список снова по высоте острова.
            if id == nil { releaseList() }
        }
    }

    // MARK: - Строка бэклога

    private var header: some View {
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
                Image(systemName: "chevron.up")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Tokens.caption)
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
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
        .padding(.horizontal, 18)
        .padding(.top, Tokens.islandHeader - Tokens.hitTarget)
        .frame(height: Tokens.islandHeader, alignment: .top)
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

    /// Тап по строке бэклога: свёрнут → раскрыт, раскрыт → свёрнут.
    private func toggle() {
        withAnimation(.spring(duration: 0.3)) { isOpen.toggle() }
    }

    /// Отпустили свайп: к ближайшему положению по тому, куда летел палец.
    private func settle(to projected: CGFloat) {
        let open = abs(openHeight - projected) < abs(collapsedHeight - projected)
        withAnimation(.spring(duration: 0.3)) { isOpen = open }
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
                windowOrigin: { plannerOrigin.point },
                onChanged: { location, start in
                    // Первое срабатывание: запомнить высоту списка, пока панель ещё не начала сворачиваться.
                    if frozenListHeight == nil { frozenListHeight = visibleListHeight }
                    onDragChanged(task, location, start)
                },
                onEnded: {
                    onDragEnded()
                    releaseList()
                },
                onCancelled: {
                    (onDragCancelled ?? onDragEnded)()
                    releaseList()
                }
            )
        )
    }

    // MARK: - Ввод

    private var inputRow: some View {
        // Строка ввода и круглая кнопка — отдельные стеклянные фигуры (без контейнера: он склеивал бы их).
        HStack(alignment: .center, spacing: 8) {
            TextField("Завтра в 10 созвон, важно", text: $input)
                .focused(inputFocus)
                .font(.system(size: 15))
                .foregroundStyle(Tokens.text)
                .padding(.horizontal, 16)
                .frame(height: Tokens.hitTarget)
                .glassEffect(.regular.tint(Tokens.field.opacity(0.5)).interactive(), in: Capsule())
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
        .padding(.horizontal, 8)
        .frame(height: Tokens.islandInput)
    }
}

/// Настройки острова бэклога.
enum BacklogSettings {
    /// Задачу вытащили из раскрытого бэклога: после переноса раскрыть его снова (`true`)
    /// или оставить свёрнутым, пока не нажмёшь сам (`false`).
    static let reopenKey = "backlogReopenAfterDrag"
}
