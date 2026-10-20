import PlannerCore
import SwiftUI

/// Панель бэклога снизу: заголовок (тап/свайп открывает), список, строка быстрого ввода.
/// Высота панели явная: 130 pt свёрнутая, при свайпе тянется за пальцем.
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
    /// Сколько высоты экрана панель может занять в открытом виде (с клавиатурой — меньше).
    var maxHeight: CGFloat = .infinity

    /// Смещение пальца во время свайпа по заголовку (вверх — отрицательное).
    @State private var dragDelta: CGFloat = 0
    /// Только что был свайп — следующий тап кнопки заголовка игнорируется.
    @State private var swiped = false

    private var openCount: Int { tasks.filter { !$0.isDone }.count }
    private var listHeight: CGFloat { tasks.isEmpty ? 48 : CGFloat(min(tasks.count, 6)) * 50 + 8 }
    private var openHeight: CGFloat {
        min(Tokens.drawerCollapsed + listHeight, max(Tokens.drawerCollapsed + 100, maxHeight))
    }

    private var hint: String {
        guard let drag = drag else { return isOpen ? "Свернуть" : "Открыть" }
        if drag.target == .backlog { return drag.fromTimeline ? "Отпусти — уберу сюда" : "Отпусти — оставлю здесь" }
        return drag.fromTimeline ? "Сюда — в бэклог" : "Тащи наверх"
    }

    private var height: CGFloat {
        let base = isOpen ? openHeight : Tokens.drawerCollapsed
        return min(openHeight, max(Tokens.drawerCollapsed, base - dragDelta))
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            list
                .frame(height: max(0, height - Tokens.drawerCollapsed), alignment: .top)
                .clipped()
                .contentShape(Rectangle())
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
        .animation(.spring(duration: 0.28), value: isOpen)
        .animation(.interactiveSpring(), value: dragDelta)
    }

    private var header: some View {
        Button {
            if swiped { swiped = false; return }
            isOpen.toggle()
        } label: {
            headerContent
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 10, coordinateSpace: .named("planner"))
                .onChanged { value in
                    dragDelta = value.translation.height
                }
                .onEnded { value in
                    let dy = value.translation.height
                    let projected = value.predictedEndTranslation.height
                    if dy < -40 || projected < -80 {
                        isOpen = true
                    } else if dy > 40 || projected > 80 {
                        isOpen = false
                    } else {
                        isOpen = height > (Tokens.drawerCollapsed + openHeight) / 2
                    }
                    dragDelta = 0
                    swiped = true
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(0.4))
                        swiped = false
                    }
                }
        )
        .accessibilityLabel(isOpen ? "Свернуть бэклог" : "Открыть бэклог")
    }

    private var headerContent: some View {
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
                }
                Spacer()
                HStack(spacing: 4) {
                    Text(hint)
                    Image(systemName: "chevron.up")
                        .font(.system(size: 13, weight: .semibold))
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                }
                .font(.system(size: 13))
                .foregroundStyle(drag == nil ? Tokens.caption : Tokens.accent)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 7)
        .frame(height: 52, alignment: .top)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .foregroundStyle(Tokens.text)
    }

    private var list: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                ForEach(tasks, id: \.id) { task in
                    row(task)
                }
                if tasks.isEmpty {
                    Text("Пусто — всё разложено по дням.")
                        .font(.system(size: 14))
                        .foregroundStyle(Tokens.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 10)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
        }
    }

    private func row(_ task: PlannerTask) -> some View {
        let style = task.quadrant.style
        return HStack(spacing: 4) {
            Button { onToggle(task) } label: {
                Circle()
                    .strokeBorder(style.dot, lineWidth: 2)
                    .background(Circle().fill(task.isDone ? style.dot : Color.clear))
                    .frame(width: 20, height: 20)
                    .frame(width: Tokens.hitTarget, height: Tokens.hitTarget)
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
        .frame(height: 50)
        .opacity(drag?.taskID == task.id ? 0.35 : (task.isDone ? 0.5 : 1))
        .foregroundStyle(Tokens.text)
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
                        .background(Tokens.accent, in: Circle())
                        .foregroundStyle(Tokens.onAccent)
                }
                .accessibilityLabel("Голосовой ввод")
            } else {
                Button(action: onSubmit) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 18, weight: .bold))
                        .frame(width: Tokens.hitTarget, height: Tokens.hitTarget)
                        .background(Tokens.accent, in: Circle())
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
