import PlannerCore
import SwiftUI

/// Единая строка задачи для списков снизу (бэклог, «Просрочено»): кружок цветом задачи, название,
/// вторая строка «когда / сколько» и проект справа, тонкий разделитель. Без лишних значков.
struct TaskRowView: View {
    let task: PlannerTask
    /// Вторая строка: «30 мин», «вчера · весь день»…
    let meta: String
    var metaIcon: String? = nil
    var metaColor: Color = Tokens.muted
    var dimmed = false
    let onToggle: () -> Void

    var body: some View {
        let style = task.style
        HStack(alignment: .top, spacing: 6) {
            Button(action: onToggle) {
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
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.leading, -10)
            .accessibilityLabel((task.isDone ? "Вернуть в работу: " : "Отметить выполненной: ") + task.title)
            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.system(size: 16))
                    .strikethrough(task.isDone)
                    .foregroundStyle(task.isDone ? Tokens.muted : Tokens.text)
                    .lineLimit(2)
                HStack(spacing: 8) {
                    Group {
                        if let metaIcon {
                            Label(meta, systemImage: metaIcon)
                        } else {
                            Text(meta)
                        }
                    }
                    .font(.system(size: 13))
                    .foregroundStyle(metaColor)
                    .lineLimit(1)
                    Spacer(minLength: 4)
                    if let project = task.project {
                        Text(project.name)
                            .font(.system(size: 13))
                            .foregroundStyle(Tokens.muted)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.top, 10)
        }
        .padding(.vertical, 8)
        .opacity(dimmed ? 0.35 : (task.isDone ? 0.6 : 1))
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1) }
    }
}
