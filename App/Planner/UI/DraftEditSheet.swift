import PlannerCore
import SwiftUI

/// Точечная правка надиктованной задачи до сохранения: название, день, время, длительность, квадрант, проект.
struct DraftEditSheet: View {
    @Binding var draft: DraftTask
    @Environment(\.dismiss) private var dismiss

    private struct DayChoice: Identifiable {
        let offset: Int?
        let title: String
        var id: String { title }
    }

    private var dayChoices: [DayChoice] {
        [DayChoice(offset: nil, title: "Бэклог")] + (0..<7).map {
            DayChoice(offset: $0, title: DayMath.label(offset: $0).capitalizedFirst)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Название", text: $draft.title)
                        .font(.system(size: 17))
                }
                Section("Когда") {
                    Picker("День", selection: $draft.dayOffset) {
                        ForEach(dayChoices) { choice in
                            Text(choice.title).tag(choice.offset)
                        }
                    }
                    if draft.dayOffset != nil {
                        Toggle("Весь день", isOn: allDayBinding)
                        if let start = draft.start {
                            Picker("Начало", selection: Binding(get: { start }, set: { draft.start = $0 })) {
                                ForEach(Array(stride(from: 0, to: ClockGrid.dayEnd, by: 15)), id: \.self) { minutes in
                                    Text(ClockGrid.format(minutes: minutes)).tag(minutes)
                                }
                            }
                        }
                    }
                    Picker("Длительность", selection: $draft.duration) {
                        ForEach(Array(stride(from: 15, through: 8 * 60, by: 15)), id: \.self) { minutes in
                            Text(ClockGrid.formatDuration(minutes)).tag(minutes)
                        }
                    }
                }
                Section("Квадрант") {
                    Picker("Квадрант", selection: $draft.quadrantRaw) {
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
                    TextField("Без проекта", text: $draft.project)
                        .textInputAutocapitalization(.sentences)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Tokens.panel)
            .navigationTitle("Задача")
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

    private var allDayBinding: Binding<Bool> {
        Binding(
            get: { draft.start == nil },
            set: { allDay in
                draft.start = allDay ? nil : max(0, min(ClockGrid.dayEnd - draft.duration, (DayMath.nowMinutes() / 15 + 1) * 15))
            }
        )
    }
}
