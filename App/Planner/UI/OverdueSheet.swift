import PlannerCore
import SwiftUI

/// Лист «Просрочено»: список с галочками и «Перенести» — на сегодня в свободные окна, на завтра, в бэклог.
struct OverdueSheet: View {
    let tasks: [PlannerTask]
    let onToggle: (PlannerTask) -> Void
    let onFitToday: () -> Void
    let onFitTomorrow: () -> Void
    let onToBacklog: () -> Void
    let onDelete: (PlannerTask) -> Void
    let onChanged: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var moveOpen = false
    @State private var editing: PlannerTask?

    private var fromLabel: String {
        let next = Int((Double(DayMath.nowMinutes()) / 15).rounded(.up)) * 15
        return "с " + ClockGrid.format(minutes: min(next, ClockGrid.dayEnd)) + ", важные — первыми"
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color(hex: 0x3A3B41))
                .frame(width: 38, height: 5)
                .padding(.top, 8)
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Text("Просрочено")
                        .font(.system(size: 17, weight: .bold))
                    Text("\(tasks.filter { !$0.isDone }.count)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(hex: 0xC9C9D1))
                        .frame(minWidth: 22, minHeight: 22)
                        .padding(.horizontal, 3)
                        .background(Tokens.badge, in: Capsule())
                }
                Spacer()
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { moveOpen.toggle() }
                } label: {
                    Text("Перенести")
                        .font(.system(size: 15, weight: .bold))
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(moveOpen ? Color(hex: 0xA93832) : Color(hex: 0xC8433C), in: Capsule())
                        .foregroundStyle(.white)
                        .frame(minHeight: Tokens.hitTarget)
                        .contentShape(Rectangle())
                }
                .disabled(tasks.isEmpty)
                Button {
                    dismiss()
                } label: {
                    Text("Готово")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Tokens.accent)
                        .frame(minWidth: Tokens.hitTarget, minHeight: Tokens.hitTarget)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Закрыть")
            }
            .padding(.leading, 18)
            .padding(.trailing, 8)
            .padding(.top, 8)
            .padding(.bottom, 10)

            if moveOpen {
                VStack(spacing: 8) {
                    Button(action: onFitToday) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("На сегодня — в свободные окна")
                                .font(.system(size: 15, weight: .bold))
                            Text(fromLabel)
                                .font(.system(size: 12))
                                .opacity(0.8)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 54)
                        .background(Tokens.accent, in: RoundedRectangle(cornerRadius: 14))
                        .foregroundStyle(Tokens.onAccent)
                    }
                    HStack(spacing: 8) {
                        Button(action: onFitTomorrow) {
                            Text("На завтра")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: Tokens.hitTarget)
                                .background(Color(hex: 0x2F3036), in: RoundedRectangle(cornerRadius: 12))
                        }
                        Button(action: onToBacklog) {
                            Text("В бэклог")
                                .font(.system(size: 15, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: Tokens.hitTarget)
                                .background(Color(hex: 0x2F3036), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
                .padding(12)
                .background(Tokens.field, in: RoundedRectangle(cornerRadius: 18))
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }

            List {
                ForEach(tasks, id: \.id) { task in
                    row(task)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 16))
                        .listRowSeparator(.hidden)
                        .contentShape(Rectangle())
                        .onTapGesture { editing = task }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button {
                                onToggle(task)
                            } label: {
                                Label(task.isDone ? "Вернуть" : "Сделано", systemImage: task.isDone ? "arrow.uturn.backward" : "checkmark")
                            }
                            .tint(Color(hex: 0x2F9E5B))
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                onDelete(task)
                            } label: {
                                Label("Удалить", systemImage: "trash")
                            }
                            Button {
                                task.day = nil
                                task.start = nil
                                onChanged()
                            } label: {
                                Label("В бэклог", systemImage: "tray.and.arrow.down")
                            }
                            .tint(Color(hex: 0x4A4B52))
                        }
                }
                if tasks.isEmpty {
                    Text("Всё чисто — просроченных нет")
                        .font(.system(size: 15))
                        .foregroundStyle(Tokens.caption)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .foregroundStyle(Tokens.text)
        .background(Tokens.panel)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(Tokens.panel)
        .sheet(item: $editing) { task in
            TaskEditSheet(task: task, onDelete: { onDelete(task) }, onChanged: onChanged)
        }
    }

    private func row(_ task: PlannerTask) -> some View {
        let style = task.style
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
