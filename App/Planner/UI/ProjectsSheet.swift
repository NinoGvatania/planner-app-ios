import SwiftData
import SwiftUI

/// Проекты: добавить, переименовать, выбрать цвет, удалить (задачи остаются без проекта).
struct ProjectsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Project.name) private var projects: [Project]
    @State private var newName = ""
    @FocusState private var newNameFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                Section("Новый проект") {
                    HStack(spacing: 8) {
                        TextField("Название", text: $newName)
                            .textInputAutocapitalization(.sentences)
                            .focused($newNameFocused)
                            .onSubmit(add)
                        Button("Добавить", action: add)
                            .disabled(trimmed.isEmpty)
                    }
                }
                Section(projects.isEmpty ? "Проектов пока нет" : "Проекты") {
                    ForEach(projects, id: \.name) { project in
                        ProjectRow(project: project, isNameTaken: { name in
                            projects.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame && $0 !== project }
                        })
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            context.delete(projects[index])
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Tokens.panel)
            .navigationTitle("Проекты")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }
                }
            }
        }
        .tint(Tokens.accent)
        .presentationDetents([.large])
        .presentationBackground(Tokens.panel)
    }

    private var trimmed: String { newName.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func add() {
        let name = trimmed.capitalizedFirst
        guard !name.isEmpty, !projects.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else { return }
        context.insert(Project(name: name, colorIndex: projects.count % ProjectPalette.colors.count))
        newName = ""
        newNameFocused = true
    }
}

/// Строка проекта: название (редактируется на месте), число задач, палитра цветов.
private struct ProjectRow: View {
    @Bindable var project: Project
    let isNameTaken: (String) -> Bool
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Circle().fill(project.color).frame(width: 14, height: 14)
                TextField("Название", text: $name)
                    .textInputAutocapitalization(.sentences)
                    .onSubmit(rename)
                    .onChange(of: name) { _, _ in rename() }
                Spacer(minLength: 0)
                Text("\(project.tasks.count)")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Tokens.muted)
            }
            HStack(spacing: 8) {
                ForEach(Array(ProjectPalette.colors.indices), id: \.self) { index in
                    Button {
                        project.colorIndex = index
                    } label: {
                        Circle()
                            .fill(ProjectPalette.color(index))
                            .frame(width: 22, height: 22)
                            .overlay(Circle().strokeBorder(Color.white, lineWidth: project.colorIndex == index ? 2.5 : 0))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Цвет \(index + 1)")
                    .accessibilityAddTraits(project.colorIndex == index ? .isSelected : [])
                }
            }
        }
        .padding(.vertical, 4)
        .onAppear { name = project.name }
    }

    private func rename() {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value != project.name, !isNameTaken(value) else { return }
        project.name = value
    }
}
