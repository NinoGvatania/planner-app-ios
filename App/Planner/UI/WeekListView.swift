import PlannerCore
import SwiftUI

/// Неделя списком: 7 секций по дням, каждая — зона сброса (время задачи сохраняется).
struct WeekListView: View {
    let tasks: [PlannerTask]
    let drag: DragState?
    let onToggle: (PlannerTask) -> Void
    let onDragChanged: (PlannerTask, CGPoint, CGPoint) -> Void
    let onDragEnded: () -> Void
    let onEdit: (PlannerTask) -> Void
    var onDragCancelled: (() -> Void)? = nil

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {
                ForEach(0..<7, id: \.self) { offset in
                    section(offset: offset)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
    }

    private func section(offset: Int) -> some View {
        let date = DayMath.day(offset: offset)
        let items = tasks
            .filter { $0.day == date }
            .sorted { ($0.start ?? -1) < ($1.start ?? -1) }
        let hovered = drag?.target == .dayTab(offset: offset)
        let title = offset == 0 ? "Сегодня" : (offset == 1 ? "Завтра" : DayMath.weekdayFull[DayMath.weekdayIndex(date)].capitalizedFirst)
        return VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(offset == 0 ? Tokens.accent : Tokens.text)
                Spacer()
                Text("\(DayMath.dayOfMonth(date)) \(DayMath.monthGenitive[DayMath.monthIndex(date)])")
                    .font(.system(size: 12))
                    .foregroundStyle(Tokens.muted)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 4)
            ForEach(items, id: \.id) { task in
                row(task)
            }
            if items.isEmpty {
                Text("Свободно — перетащи сюда задачу")
                    .font(.system(size: 13))
                    .foregroundStyle(Tokens.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.bottom, 10)
                    .padding(.top, 2)
            }
        }
        .padding(.top, 10)
        .padding(.horizontal, 6)
        .padding(.bottom, 4)
        .background(hovered ? Tokens.accent.opacity(0.12) : Color(hex: 0x141518), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(hovered ? Tokens.accent : Color.white.opacity(0.05), lineWidth: 1))
        // Секции лежат в ScrollView: рамки сообщаются только во время перетаскивания,
        // иначе каждый кадр прокрутки перерисовывал бы весь экран.
        .reportZone("tab-\(offset)", enabled: drag != nil)
    }

    private func row(_ task: PlannerTask) -> some View {
        let style = task.style
        return HStack(spacing: 2) {
            Text(task.start.map { ClockGrid.format(minutes: $0) } ?? "весь день")
                .font(.system(size: 13))
                .monospacedDigit()
                .foregroundStyle(Tokens.caption)
                .frame(width: 70, alignment: .leading)
                .padding(.leading, 8)
            Button { onToggle(task) } label: {
                ZStack {
                    Circle()
                        .strokeBorder(style.dot, lineWidth: 2)
                        .background(Circle().fill(task.isDone ? style.dot : Color.clear))
                        .frame(width: 20, height: 20)
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
            .accessibilityLabel((task.isDone ? "Вернуть в работу: " : "Отметить выполненной: ") + task.title)
            Text(task.title)
                .font(.system(size: 15))
                .lineLimit(1)
                .strikethrough(task.isDone)
            Spacer(minLength: 4)
            Text(task.project?.name ?? "")
                .font(.system(size: 12))
                .foregroundStyle(Tokens.muted)
                .lineLimit(1)
                .frame(maxWidth: 90, alignment: .trailing)
                .padding(.trailing, 8)
        }
        .frame(minHeight: 46)
        .opacity(drag?.taskID == task.id ? 0.35 : (task.isDone ? 0.5 : 1))
        .contentShape(Rectangle())
        .onTapGesture { onEdit(task) }
        .gesture(HoldDragGesture(onChanged: { location, start in onDragChanged(task, location, start) }, onEnded: onDragEnded, onCancelled: onDragCancelled ?? onDragEnded))
    }
}
