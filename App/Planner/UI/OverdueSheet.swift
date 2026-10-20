import PlannerCore
import SwiftUI

/// Лист «Просрочено»: список с галочками. Кнопка «Перенести» — следующий шаг этапа 1.
struct OverdueSheet: View {
    let tasks: [PlannerTask]
    let onToggle: (PlannerTask) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color(hex: 0x3A3B41))
                .frame(width: 38, height: 5)
                .padding(.top, 8)
            HStack(spacing: 8) {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: Tokens.hitTarget, height: Tokens.hitTarget)
                        .background(Tokens.badge, in: Circle())
                }
                .accessibilityLabel("Закрыть")
                Text("Просрочено")
                    .font(.system(size: 17, weight: .bold))
                    .frame(maxWidth: .infinity)
                Button {
                    // Перенос по свободным окнам появится следующим шагом.
                } label: {
                    Text("Перенести")
                        .font(.system(size: 15, weight: .bold))
                        .padding(.horizontal, 16)
                        .frame(height: Tokens.hitTarget)
                        .background(Color(hex: 0xC8433C), in: Capsule())
                        .foregroundStyle(.white)
                }
                .disabled(true)
                .opacity(0.5)
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 12)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(tasks, id: \.id) { task in
                        row(task)
                    }
                    if tasks.isEmpty {
                        Text("Всё чисто — просроченных нет")
                            .font(.system(size: 15))
                            .foregroundStyle(Tokens.caption)
                            .padding(.vertical, 24)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .foregroundStyle(Tokens.text)
        .background(Tokens.panel)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(Tokens.panel)
    }

    private func row(_ task: PlannerTask) -> some View {
        let style = task.quadrant.style
        let dayLabel = task.day.map { DayMath.label(offset: DayMath.offset(of: $0)) } ?? ""
        let when = task.start.map { "\(dayLabel) · " + ClockGrid.format(minutes: $0) + "–" + ClockGrid.format(minutes: $0 + task.duration) } ?? "\(dayLabel) · весь день"
        return HStack(alignment: .top, spacing: 6) {
            Button { onToggle(task) } label: {
                ZStack {
                    Circle()
                        .strokeBorder(style.dot, lineWidth: 2)
                        .background(Circle().fill(task.isDone ? style.dot : Color.clear))
                        .frame(width: 24, height: 24)
                    if task.isDone {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(Tokens.background)
                    }
                }
                .frame(width: Tokens.hitTarget, height: Tokens.hitTarget)
            }
            .buttonStyle(.plain)
            .padding(.leading, -10)
            .accessibilityLabel((task.isDone ? "Вернуть в работу: " : "Отметить выполненной: ") + task.title)
            VStack(alignment: .leading, spacing: 5) {
                Text(task.title)
                    .font(.system(size: 16))
                    .strikethrough(task.isDone)
                    .foregroundStyle(task.isDone ? Tokens.muted : Tokens.text)
                HStack {
                    Label(when, systemImage: "calendar")
                        .font(.system(size: 13))
                        .foregroundStyle(Tokens.overdue)
                        .lineLimit(1)
                    Spacer()
                    Text(task.project?.name ?? "")
                        .font(.system(size: 13))
                        .foregroundStyle(Tokens.muted)
                }
            }
            .padding(.top, 10)
        }
        .padding(.vertical, 8)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1) }
    }
}
