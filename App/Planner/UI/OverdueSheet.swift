import PlannerCore
import SwiftUI

/// Лист «Просрочено»: список с галочками и «Перенести» — на сегодня на весь день, на завтра, в бэклог.
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

    var body: some View {
        VStack(spacing: 0) {
            // Шапка и панель «Перенести» — в одном обрезанном блоке: панель выезжает из‑под шапки,
            // список под ней съезжает вниз с той же скоростью, ничего не накрывает друг друга.
            VStack(spacing: 0) {
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
                }
                .padding(.leading, 18)
                .padding(.trailing, 14)
                .padding(.top, 18)
                .padding(.bottom, 10)
                .background(Tokens.panel)
                .zIndex(1)

                if moveOpen {
                    VStack(spacing: 8) {
                        Button(action: onFitToday) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("На сегодня — на весь день")
                                    .font(.system(size: 15, weight: .bold))
                                Text("без времени — расставишь сам")
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
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .clipped()

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
        .presentationDragIndicator(.visible)
        .presentationBackground(Tokens.panel)
        .sheet(item: $editing) { task in
            TaskEditSheet(task: task, onDelete: { onDelete(task) }, onChanged: onChanged)
        }
    }

    private func row(_ task: PlannerTask) -> some View {
        let dayLabel = task.day.map { DayMath.label(offset: DayMath.offset(of: $0)) } ?? ""
        let when = task.start.map { "\(dayLabel) · " + ClockGrid.format(minutes: $0) + "–" + ClockGrid.format(minutes: $0 + task.duration) } ?? "\(dayLabel) · весь день"
        return TaskRowView(task: task, meta: when, metaIcon: "calendar", metaColor: Tokens.overdue, onToggle: { onToggle(task) })
    }
}
