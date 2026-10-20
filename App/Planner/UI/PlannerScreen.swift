import Foundation
import PlannerCore
import SwiftData
import SwiftUI

/// Единственный экран приложения: шапка, рабочая поверхность, панель бэклога.
struct PlannerScreen: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PlannerTask.createdAt) private var tasks: [PlannerTask]

    @State private var dayOffset = 0
    @State private var mode: ViewMode = .day
    @State private var showDone = true
    @State private var drawerOpen = false
    @State private var showOverdue = false
    @State private var input = ""
    @State private var toast: String?
    @State private var toastTask: Task<Void, Never>?

    private var today: Date { DayMath.today() }
    private var visibleTasks: [PlannerTask] { showDone ? tasks : tasks.filter { !$0.isDone } }
    private var overdueTasks: [PlannerTask] {
        tasks.filter { $0.isOverdue(today: today) }
            .sorted { ($0.day ?? today, $0.start ?? 0) < ($1.day ?? today, $1.start ?? 0) }
    }
    private var backlogTasks: [PlannerTask] {
        tasks.filter { $0.isInBacklog && (!$0.isDone || showDone) }
            .sorted { a, b in
                if a.isDone != b.isDone { return !a.isDone }
                return a.backlogRank > b.backlogRank
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            HeaderView(
                title: mode == .day ? DayMath.title(offset: dayOffset) : mode.title,
                subtitle: mode == .day ? DayMath.subtitle(offset: dayOffset) : "Скоро",
                overdueCount: overdueTasks.count,
                todayNumber: DayMath.dayOfMonth(today),
                mode: $mode,
                showDone: $showDone,
                onOverdue: { showOverdue = true },
                onToday: { withAnimation { dayOffset = 0 } }
            )

            if mode == .day {
                WeekStripView(dayOffset: $dayOffset, hasTasks: { offset in
                    let date = DayMath.day(offset: offset)
                    return visibleTasks.contains { $0.day == date }
                })
                DayTimelineView(
                    timed: dayTasks.filter { $0.start != nil },
                    allDay: dayTasks.filter { $0.start == nil },
                    showNow: dayOffset == 0,
                    onToggle: toggleDone
                )
                .id(dayOffset)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: mode.symbol)
                        .font(.system(size: 40))
                        .foregroundStyle(Tokens.muted)
                    Text("Вид «\(mode.title)» появится на этапе 2")
                        .font(.system(size: 15))
                        .foregroundStyle(Tokens.caption)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            BacklogDrawerView(
                tasks: backlogTasks,
                isOpen: $drawerOpen,
                input: $input,
                onSubmit: submitInput,
                onVoice: { showToast("Голосовой ввод появится на этапе 2") },
                onToggle: toggleDone
            )
        }
        .background(Tokens.background.ignoresSafeArea())
        .foregroundStyle(Tokens.text)
        .overlay(alignment: .bottom) {
            if let toast = toast {
                Text(toast)
                    .font(.system(size: 14))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Tokens.badge, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.4), radius: 12, y: 8)
                    .padding(.horizontal, 16)
                    .padding(.bottom, Tokens.drawerCollapsed + 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .animation(.easeOut(duration: 0.22), value: toast)
        .sheet(isPresented: $showOverdue) {
            OverdueSheet(tasks: overdueTasks, onToggle: toggleDone)
        }
        .task {
            SeedData.seedIfNeeded(in: context)
        }
    }

    private var dayTasks: [PlannerTask] {
        let date = DayMath.day(offset: dayOffset)
        return visibleTasks.filter { $0.day == date }
    }

    // MARK: - Действия

    private func toggleDone(_ task: PlannerTask) {
        task.isDone.toggle()
        task.completedAt = task.isDone ? Date() : nil
        if task.isDone, task.isInBacklog {
            showToast("Готово: «\(task.title)»")
        }
    }

    private func submitInput() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        input = ""
        let parser = QuickAddParser()
        switch parser.parse(text) {
        case .task(let parsed):
            addTask(parsed)
        case .agenda(let offset):
            let date = DayMath.day(offset: offset)
            let items = tasks
                .filter { $0.day == date && !$0.isDone }
                .sorted { ($0.start ?? -1) < ($1.start ?? -1) }
            let summary = items.isEmpty
                ? "ничего не запланировано"
                : items.map { ($0.start.map { ClockGrid.format(minutes: $0) + " " } ?? "") + $0.title }.joined(separator: "; ")
            showToast(DayMath.label(offset: offset).capitalizedFirst + ": " + summary)
        case .fitOverdue:
            showToast("Раскладка просроченных по окнам появится следующим шагом")
        }
    }

    private func addTask(_ parsed: ParsedTask) {
        let project = parsed.project.map { findOrCreateProject(named: $0) }
        let rank = (tasks.map { $0.backlogRank }.max() ?? 0) + 1
        let task = PlannerTask(
            title: parsed.title,
            day: parsed.dayOffset.map { DayMath.day(offset: $0) },
            start: parsed.start,
            duration: parsed.duration,
            quadrant: parsed.quadrant,
            project: project,
            backlogRank: rank
        )
        context.insert(task)
        if let offset = parsed.dayOffset, mode == .day, (0...6).contains(offset) {
            dayOffset = offset
        }
        let when: String
        if let offset = parsed.dayOffset {
            if let start = parsed.start {
                when = DayMath.label(offset: offset) + " · " + ClockGrid.format(minutes: start) + "–" + ClockGrid.format(minutes: start + parsed.duration)
            } else {
                when = DayMath.label(offset: offset) + " · весь день"
            }
        } else {
            when = "в бэклог"
        }
        let quadrantNote = parsed.quadrant == .other ? "" : " · " + parsed.quadrant.name.lowercased()
        showToast("«\(parsed.title)» — \(when)\(quadrantNote)")
    }

    private func findOrCreateProject(named name: String) -> Project {
        let descriptor = FetchDescriptor<Project>(predicate: #Predicate<Project> { $0.name == name })
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let project = Project(name: name)
        context.insert(project)
        return project
    }

    private func showToast(_ message: String) {
        toastTask?.cancel()
        toast = message
        toastTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2.8))
            if !Task.isCancelled {
                toast = nil
            }
        }
    }
}

private extension String {
    var capitalizedFirst: String {
        guard let first = first else { return self }
        return String(first).uppercased() + dropFirst()
    }
}
