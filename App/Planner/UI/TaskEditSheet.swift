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

    @State private var projectName: String = ""
    @State private var confirmDelete = false

    private var dayOffset: Int? { task.day.map { DayMath.offset(of: $0) } }

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
        for offset in 0..<7 {
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
                    Picker("Длительность", selection: $task.duration) {
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
                                    .tint(task.project?.name == project.name ? project.color : Tokens.caption)
                                }
                            }
                        }
                    }
                }
                Section {
                    Toggle("Сделана", isOn: doneBinding)
                    Toggle("Ежедневная рутина", isOn: $task.isRoutine)
                }
                Section {
                    Button("Удалить задачу", role: .destructive) { confirmDelete = true }
                        .frame(maxWidth: .infinity)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Tokens.panel)
            .navigationTitle("Задача")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
        .onChange(of: task.title) { _, _ in onChanged() }
        .onChange(of: task.duration) { _, _ in onChanged() }
        .onChange(of: task.quadrantRaw) { _, _ in onChanged() }
        .onChange(of: task.isRoutine) { _, isRoutine in
            if isRoutine {
                RoutineManager.enable(task, in: context)
            } else {
                RoutineManager.disable(task, in: context)
            }
            onChanged()
        }
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
            set: { task.start = $0; onChanged() }
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
