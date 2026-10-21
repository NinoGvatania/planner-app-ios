import PlannerCore
import SwiftData
import SwiftUI

/// Редактирование задачи: название, день, время, длительность, квадрант, проект, удаление.
/// Изменения применяются сразу (модель SwiftData), лист просто закрывается.
struct TaskEditSheet: View {
    @Bindable var task: PlannerTask
    let onDelete: () -> Void
    let onChanged: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Project.name) private var projects: [Project]
    @Query private var routines: [Routine]

    @State private var projectName: String = ""
    @State private var confirmDelete = false

    private var dayOffset: Int? { task.day.map { DayMath.offset(of: $0) } }
    private var routine: Routine? { routines.first { $0.title == task.title } }
    /// Дни недели по порядку с понедельника в значениях `Calendar.weekday`.
    private let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]

    private struct DayChoice: Identifiable {
        let offset: Int?
        let title: String
        var id: String { title }
    }

    private var dayChoices: [DayChoice] {
        var list = [DayChoice(offset: nil, title: "Бэклог")]
        if let offset = dayOffset, offset < 0 {
            list.append(DayChoice(offset: offset, title: DayMath.label(offset: offset).capitalizedFirst))
        }
        for offset in 0...7 {
            list.append(DayChoice(offset: offset, title: DayMath.label(offset: offset).capitalizedFirst))
        }
        if let offset = dayOffset, offset > 7 {
            list.append(DayChoice(offset: offset, title: DayMath.label(offset: offset).capitalizedFirst))
        }
        return list
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Название", text: $task.title)
                        .font(.system(size: 17))
                }
                Section("Когда") {
                    Picker("День", selection: dayBinding) {
                        ForEach(dayChoices) { choice in
                            Text(choice.title).tag(choice.offset)
                        }
                    }
                    if task.day != nil {
                        Toggle("Весь день", isOn: allDayBinding)
                        if task.start != nil {
                            Picker("Начало", selection: startBinding) {
                                ForEach(Array(stride(from: 0, to: ClockGrid.dayEnd, by: 15)), id: \.self) { minutes in
                                    Text(ClockGrid.format(minutes: minutes)).tag(minutes)
                                }
                            }
                        }
                    }
                    Picker("Длительность", selection: durationBinding) {
                        ForEach(Array(stride(from: 15, through: 8 * 60, by: 15)), id: \.self) { minutes in
                            Text(ClockGrid.formatDuration(minutes)).tag(minutes)
                        }
                    }
                }
                Section("Квадрант") {
                    Picker("Квадрант", selection: $task.quadrantRaw) {
                        HStack(spacing: 8) {
                            Circle().fill(QuadrantStyle.unsorted.dot).frame(width: 10, height: 10)
                            Text("Не разобрано")
                        }
                        .tag(0)
                        ForEach(Quadrant.allCases, id: \.rawValue) { quadrant in
                            HStack(spacing: 8) {
                                Circle().fill(quadrant.style.dot).frame(width: 10, height: 10)
                                Text(quadrant.name)
                            }
                            .tag(quadrant.rawValue)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section("Проект") {
                    TextField("Без проекта", text: $projectName)
                        .textInputAutocapitalization(.sentences)
                        .onSubmit(applyProject)
                    if !projects.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(projects, id: \.name) { project in
                                    Button {
                                        projectName = project.name
                                        applyProject()
                                    } label: {
                                        HStack(spacing: 6) {
                                            Circle().fill(project.color).frame(width: 8, height: 8)
                                            Text(project.name)
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.large)
                                    .tint(task.project?.name == project.name ? project.color : Tokens.caption)
                                }
                            }
                        }
                    }
                }
                Section {
                    Toggle("Сделана", isOn: doneBinding)
                    Toggle("Повторять", isOn: $task.isRoutine)
                } footer: {
                    if task.isRoutine {
                        Text("Копии создаются на неделю вперёд по расписанию ниже; время и длительность — из этой задачи.")
                    }
                }
                if task.isRoutine, let routine = routine {
                    routineSection(routine)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Tokens.panel)
            .navigationTitle("Задача")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .tint(Tokens.overdue)
                    .accessibilityLabel("Удалить задачу")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        applyProject()
                        onChanged()
                        dismiss()
                    }
                }
            }
            .confirmationDialog("Удалить «\(task.title)»?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Удалить", role: .destructive) {
                    onDelete()
                    dismiss()
                }
                Button("Отмена", role: .cancel) {}
            }
        }
        .tint(Tokens.accent)
        .presentationDetents([.large])
        .presentationBackground(Tokens.panel)
        .onAppear { projectName = task.project?.name ?? "" }
        .onDisappear { applyProject() }
        .onChange(of: task.title) { _, _ in onChanged() }
        .onChange(of: task.duration) { _, _ in onChanged() }
        .onChange(of: task.quadrantRaw) { _, _ in
            syncRoutine()
            onChanged()
        }
        .onChange(of: task.isRoutine) { _, isRoutine in
            if isRoutine {
                RoutineManager.enable(task, in: context)
            } else {
                RoutineManager.disable(task, in: context)
            }
            onChanged()
        }
    }

    // MARK: - Повтор

    @ViewBuilder
    private func routineSection(_ routine: Routine) -> some View {
        Section("Расписание") {
            VStack(alignment: .leading, spacing: 8) {
                Text(routine.weekdays.isEmpty ? "Каждый день" : "По дням недели")
                    .font(.system(size: 13))
                    .foregroundStyle(Tokens.caption)
                HStack(spacing: 6) {
                    ForEach(weekdayOrder, id: \.self) { weekday in
                        let selected = routine.weekdays.isEmpty || routine.weekdays.contains(weekday)
                        Button {
                            toggleWeekday(weekday, in: routine)
                        } label: {
                            Text(DayMath.weekdayShort[weekday - 1])
                                .font(.system(size: 13, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .frame(height: Tokens.hitTarget)
                                .background(selected ? Tokens.accent : Tokens.field, in: RoundedRectangle(cornerRadius: 10))
                                .foregroundStyle(selected ? Tokens.onAccent : Tokens.caption)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(DayMath.weekdayFull[weekday - 1])
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
            .padding(.vertical, 4)
            Picker("Недели", selection: Binding(
                get: { routine.weekParity },
                set: { value in
                    routine.weekParity = value
                    RoutineManager.regenerate(routine, keeping: task, in: context)
                    onChanged()
                }
            )) {
                Text("Каждую").tag(0)
                Text("Нечётные").tag(1)
                Text("Чётные").tag(2)
            }
            if let start = task.start {
                LabeledContent("Время", value: ClockGrid.format(minutes: start) + " · " + ClockGrid.formatDuration(task.duration))
            } else {
                LabeledContent("Время", value: "весь день")
            }
        }
    }

    private func toggleWeekday(_ weekday: Int, in routine: Routine) {
        var days = routine.weekdays.isEmpty ? weekdayOrder : routine.weekdays
        if days.contains(weekday) {
            days.removeAll { $0 == weekday }
            if days.isEmpty { days = [weekday] }
        } else {
            days.append(weekday)
        }
        routine.weekdays = days.count == 7 ? [] : days
        RoutineManager.regenerate(routine, keeping: task, in: context)
        onChanged()
    }

    /// Время и длительность задачи поменялись — шаблон рутины повторяет их.
    private func syncRoutine() {
        guard task.isRoutine, let routine = routine else { return }
        var changed = false
        if let start = task.start, routine.start != start { routine.start = start; changed = true }
        if routine.duration != task.duration { routine.duration = task.duration; changed = true }
        if routine.quadrantRaw != task.quadrantRaw { routine.quadrantRaw = task.quadrantRaw; changed = true }
        if changed { RoutineManager.regenerate(routine, keeping: task, in: context) }
    }

    // MARK: - Привязки

    private var dayBinding: Binding<Int?> {
        Binding(
            get: { dayOffset },
            set: { newValue in
                if let offset = newValue {
                    task.day = DayMath.day(offset: offset)
                } else {
                    task.day = nil
                    task.start = nil
                }
                onChanged()
            }
        )
    }

    private var allDayBinding: Binding<Bool> {
        Binding(
            get: { task.start == nil },
            set: { allDay in
                task.start = allDay ? nil : max(0, min(ClockGrid.dayEnd - task.duration, (DayMath.nowMinutes() / 15 + 1) * 15))
                onChanged()
            }
        )
    }

    private var startBinding: Binding<Int> {
        Binding(
            get: { task.start ?? 0 },
            set: { start in
                task.start = start
                task.duration = max(15, min(task.duration, ClockGrid.dayEnd - start))
                syncRoutine()
                onChanged()
            }
        )
    }

    /// Длительность не выходит за 24:00.
    private var durationBinding: Binding<Int> {
        Binding(
            get: { task.duration },
            set: { duration in
                task.duration = max(15, min(duration, ClockGrid.dayEnd - (task.start ?? 0)))
                syncRoutine()
                onChanged()
            }
        )
    }

    private var doneBinding: Binding<Bool> {
        Binding(
            get: { task.isDone },
            set: { done in
                task.isDone = done
                task.completedAt = done ? Date() : nil
                onChanged()
            }
        )
    }

    private func applyProject() {
        let name = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            task.project = nil
        } else if let existing = projects.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            task.project = existing
        } else {
            let project = Project(name: name.capitalizedFirst, colorIndex: projects.count % ProjectPalette.colors.count)
            context.insert(project)
            task.project = project
        }
        onChanged()
    }
}
