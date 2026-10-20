import PlannerCore
import SwiftUI

/// Блок задачи на сетке дня.
struct TaskBlockView: View {
    let task: PlannerTask
    let height: CGFloat
    /// Узкая колонка (3 дня или несколько параллельных задач).
    let compact: Bool
    let onToggle: () -> Void

    private var tall: Bool { height >= (compact ? 46 : 40) }
    private var titleSize: CGFloat { compact ? 11 : 13 }
    private var timeSize: CGFloat { compact ? 11 : 11.5 }

    private var timeRange: String {
        guard let start = task.start else { return "" }
        return ClockGrid.format(minutes: start) + "–" + ClockGrid.format(minutes: start + task.duration)
    }

    private var lines: Int {
        let lineHeight = titleSize * 1.25
        let available = height - (compact ? 6 : 10) - timeSize - 6
        return max(1, Int(available / lineHeight))
    }

    var body: some View {
        let style = task.quadrant.style
        HStack(alignment: tall ? .top : .center, spacing: 3) {
            Button(action: onToggle) {
                ZStack {
                    Circle()
                        .strokeBorder(style.dot, lineWidth: 2)
                        .background(Circle().fill(task.isDone ? style.dot : Color.clear))
                        .frame(width: compact ? 13 : 16, height: compact ? 13 : 16)
                    if task.isDone {
                        Image(systemName: "checkmark")
                            .font(.system(size: compact ? 7 : 9, weight: .heavy))
                            .foregroundStyle(Tokens.background)
                    }
                }
                .frame(width: compact ? 26 : 34)
                .frame(maxHeight: .infinity, alignment: tall ? .top : .center)
                .padding(.top, tall ? 1 : 0)
            }
            .buttonStyle(.plain)
            .accessibilityLabel((task.isDone ? "Вернуть в работу: " : "Отметить выполненной: ") + task.title)

            if tall {
                VStack(alignment: .leading, spacing: 2) {
                    Text(task.title)
                        .font(.system(size: titleSize, weight: .semibold))
                        .lineLimit(lines)
                        .strikethrough(task.isDone)
                    Text(compact ? ClockGrid.format(minutes: task.start ?? 0) : timeRange)
                        .font(.system(size: timeSize))
                        .monospacedDigit()
                        .opacity(0.8)
                        .lineLimit(1)
                }
                .padding(.top, 1)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 6) {
                    Text(task.title)
                        .font(.system(size: titleSize, weight: .semibold))
                        .lineLimit(1)
                        .strikethrough(task.isDone)
                    if !compact {
                        Spacer(minLength: 0)
                        Text(ClockGrid.format(minutes: task.start ?? 0))
                            .font(.system(size: timeSize))
                            .monospacedDigit()
                            .opacity(0.8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, tall ? (compact ? 3 : 5) : 0)
        .padding(.trailing, compact ? 4 : 8)
        .frame(height: height)
        .foregroundStyle(style.text)
        .background(style.background, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(style.border, lineWidth: 1.5))
        .opacity(task.isDone ? 0.55 : 1)
        .clipped()
    }
}
