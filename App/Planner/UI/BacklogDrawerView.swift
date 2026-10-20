import PlannerCore
import SwiftUI

/// Панель бэклога снизу: заголовок (тап/свайп открывает), список, строка быстрого ввода.
struct BacklogDrawerView: View {
    let tasks: [PlannerTask]
    @Binding var isOpen: Bool
    @Binding var input: String
    let onSubmit: () -> Void
    let onVoice: () -> Void
    let onToggle: (PlannerTask) -> Void

    @State private var dragOffset: CGFloat = 0

    private var openCount: Int { tasks.filter { !$0.isDone }.count }
    private var listHeight: CGFloat { tasks.isEmpty ? 48 : CGFloat(min(tasks.count, 6)) * 50 + 8 }

    var body: some View {
        VStack(spacing: 0) {
            header
            if isOpen {
                list
            }
            inputRow
        }
        .frame(maxWidth: .infinity)
        .background(Tokens.drawer)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22))
        .overlay(alignment: .top) {
            UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.45), radius: 15, y: -10)
        .animation(.spring(duration: 0.28), value: isOpen)
    }

    private var header: some View {
        Button {
            isOpen.toggle()
        } label: {
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
                        Text(isOpen ? "Свернуть" : "Открыть")
                        Image(systemName: "chevron.up")
                            .font(.system(size: 13, weight: .semibold))
                            .rotationEffect(.degrees(isOpen ? 180 : 0))
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(Tokens.caption)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 7)
            .frame(height: 52, alignment: .top)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Tokens.text)
        .accessibilityLabel(isOpen ? "Свернуть бэклог" : "Открыть бэклог")
        .simultaneousGesture(
            DragGesture(minimumDistance: 12)
                .onEnded { value in
                    if value.translation.height < -40 {
                        isOpen = true
                    } else if value.translation.height > 40 {
                        isOpen = false
                    }
                }
        )
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
        .frame(height: listHeight)
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
        .opacity(task.isDone ? 0.5 : 1)
        .foregroundStyle(Tokens.text)
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
        .frame(height: 76, alignment: .top)
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) }
    }
}
