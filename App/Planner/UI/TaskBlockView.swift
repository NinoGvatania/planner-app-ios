import PlannerCore
import SwiftUI

/// Блок задачи на сетке дня.
struct TaskBlockView: View {
    let task: PlannerTask
    let height: CGFloat
    /// Узкая колонка (несколько параллельных задач).
    let compact: Bool
    /// Очень узкая колонка (сетка недели): без кружка, только название.
    var narrow: Bool = false
    var selected: Bool = false
    /// Длительность во время растягивания (иначе — из задачи).
    var liveDuration: Int? = nil
    var dimmed: Bool = false
    let onToggle: () -> Void

    private var duration: Int { liveDuration ?? task.duration }
    private var tall: Bool { height >= (compact ? 46 : 40) }
    private var titleSize: CGFloat { compact ? 11 : 13 }
    private var timeSize: CGFloat { compact ? 11 : 11.5 }

    private var timeText: String {
        guard let start = task.start else { return "" }
        if compact {
            return selected ? ClockGrid.formatDuration(duration) : ClockGrid.format(minutes: start)
        }
        let range = ClockGrid.format(minutes: start) + "–" + ClockGrid.format(minutes: start + duration)
        return selected ? range + " · " + ClockGrid.formatDuration(duration) : range
    }

    private var shortTimeText: String {
        guard let start = task.start else { return "" }
        return selected ? ClockGrid.formatDuration(duration) : ClockGrid.format(minutes: start)
    }

    private var lines: Int {
        let lineHeight = titleSize * 1.25
        let available = height - (compact ? 6 : 10) - (narrow ? 0 : timeSize + 6)
        return max(1, Int(available / lineHeight))
    }

    var body: some View {
        let style = task.quadrant.style
        HStack(alignment: tall ? .top : .center, spacing: 3) {
            if narrow {
                Text(task.title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(max(1, lines))
                    .strikethrough(task.isDone)
                    .padding(.leading, 5)
                    .padding(.top, tall ? 2 : 0)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
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
                        Text(timeText)
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
                        if !compact || selected {
                            Spacer(minLength: 0)
                            Text(shortTimeText)
                                .font(.system(size: timeSize))
                                .monospacedDigit()
                                .opacity(0.8)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.vertical, tall ? (compact ? 3 : 5) : 0)
        .padding(.trailing, compact ? 4 : 8)
        .frame(height: height)
        .foregroundStyle(style.text)
        .background(style.background, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(selected ? Color.white : style.border, lineWidth: 1.5))
        .shadow(color: Color.black.opacity(selected ? 0.5 : 0), radius: 11, y: 8)
        .opacity(dimmed ? 0.35 : (task.isDone ? 0.55 : 1))
        .clipped()
    }
}
