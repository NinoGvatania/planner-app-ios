import PlannerCore
import SwiftUI

/// Лист серии: огонёк, дни подряд, неделя точками, лучшая серия — и «кладбище»: история выполненных
/// задач по дням, любую можно вернуть в работу.
struct StreakSheet: View {
    let info: Streak.Info
    /// Выполненные задачи, свежие сверху.
    let done: [PlannerTask]
    /// Вернуть задачу в работу (снять галочку).
    let onRestore: (PlannerTask) -> Void
    @Environment(\.dismiss) private var dismiss

    private let flame = Color(hex: 0xFF9F43)
    private var dayLetters: [String] { ["пн", "вт", "ср", "чт", "пт", "сб", "вс"] }
    private var todayIndex: Int { (DayMath.weekdayIndex(DayMath.today()) + 6) % 7 }

    private var headline: String {
        switch info.current {
        case 0: return "Серия не начата"
        default: return "\(info.current) " + DayMath.plural(info.current, "день", "дня", "дней") + " подряд"
        }
    }

    private var hint: String {
        if info.current == 0 { return "Сделай сегодня хотя бы одну задачу — и серия начнётся." }
        if info.todayClosed { return "Сегодня уже закрыто: сделано \(info.todayDone) " + DayMath.plural(info.todayDone, "задача", "задачи", "задач") + ". Так держать!" }
        return "Сегодня ещё ничего не сделано — закрой хотя бы одну задачу, чтобы серия не прервалась."
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                streakBlock
                graveyard
            }
            .padding(.bottom, 12)
        }
        .scrollIndicators(.hidden)
        .safeAreaInset(edge: .bottom) {
            Button {
                dismiss()
            } label: {
                Text("Готово")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Tokens.onAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Tokens.accent, in: RoundedRectangle(cornerRadius: 14))
                    .contentShape(Rectangle())
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 16)
            .background(Tokens.panel)
        }
        .foregroundStyle(Tokens.text)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tokens.panel)
        .presentationDetents([.fraction(0.72), .large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(Tokens.panel)
    }

    private var streakBlock: some View {
        VStack(spacing: 18) {
            Capsule()
                .fill(Color(hex: 0x3A3B41))
                .frame(width: 38, height: 5)
                .padding(.top, 8)
            Image(systemName: info.current > 0 ? "flame.fill" : "flame")
                .font(.system(size: 64, weight: .bold))
                .foregroundStyle(info.current > 0 ? flame : Tokens.muted)
                .shadow(color: info.current > 0 ? flame.opacity(0.55) : .clear, radius: 24)
                .padding(.top, 6)
            Text(headline)
                .font(.system(size: 24, weight: .bold))
            Text(hint)
                .font(.system(size: 14))
                .foregroundStyle(Tokens.caption)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            HStack(spacing: 10) {
                ForEach(0..<7, id: \.self) { index in
                    let closed = info.week[index]
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(closed ? flame : Tokens.cluster)
                                .frame(width: 34, height: 34)
                            if closed {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .heavy))
                                    .foregroundStyle(Color(hex: 0x2A1200))
                            } else if index == todayIndex {
                                Circle().strokeBorder(flame, lineWidth: 2).frame(width: 34, height: 34)
                            }
                        }
                        Text(dayLetters[index])
                            .font(.system(size: 11, weight: index == todayIndex ? .bold : .regular))
                            .foregroundStyle(index == todayIndex ? Tokens.text : Tokens.muted)
                    }
                }
            }
            .padding(.top, 6)
            HStack(spacing: 10) {
                stat("\(info.best)", label: "лучшая серия")
                stat("\(info.todayDone)", label: "сделано сегодня")
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: - Кладбище задач

    /// Дни с выполненными задачами, свежие сверху; без даты выполнения — в конце, «Раньше».
    private struct GraveDay: Identifiable {
        let id: String
        let title: String
        let tasks: [PlannerTask]
    }

    private var graveyardDays: [GraveDay] {
        let cal = DayMath.calendar
        let today = DayMath.today()
        var groups: [Date?: [PlannerTask]] = [:]
        for task in done {
            groups[task.completedAt.map { cal.startOfDay(for: $0) }, default: []].append(task)
        }
        let days = groups.keys.sorted { a, b in
            switch (a, b) {
            case let (a?, b?): return a > b
            case (nil, _): return false
            case (_, nil): return true
            }
        }
        return days.map { day in
            let tasks = (groups[day] ?? []).sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
            guard let day else { return GraveDay(id: "earlier", title: "Раньше", tasks: tasks) }
            let offset = DayMath.offset(of: day) - DayMath.offset(of: today)
            let title = offset == 0 ? "Сегодня" : (offset == -1 ? "Вчера"
                : DayMath.weekdayShort[DayMath.weekdayIndex(day)].capitalizedFirst + ", \(DayMath.dayOfMonth(day)) "
                    + DayMath.monthGenitive[DayMath.monthIndex(day)])
            return GraveDay(id: "\(day.timeIntervalSinceReferenceDate)", title: title, tasks: tasks)
        }
    }

    private var graveyard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Кладбище задач")
                    .font(.system(size: 17, weight: .bold))
                Spacer(minLength: 8)
                Text("\(done.count)")
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Tokens.caption)
            }
            Text("Всё сделанное. Нажми на кружок — задача вернётся в работу.")
                .font(.system(size: 12))
                .foregroundStyle(Tokens.caption)
            if done.isEmpty {
                Text("Пока пусто — здесь будут выполненные задачи.")
                    .font(.system(size: 14))
                    .foregroundStyle(Tokens.muted)
                    .frame(maxWidth: .infinity, minHeight: 60)
            }
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(graveyardDays) { group in
                    Text(group.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Tokens.caption)
                        .padding(.top, 10)
                        .padding(.bottom, 2)
                    ForEach(group.tasks) { task in
                        TaskRowView(task: task, meta: graveMeta(task), dimmed: true) {
                            withAnimation(.easeOut(duration: 0.2)) { onRestore(task) }
                        }
                        .background(Tokens.cluster, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
    }

    /// «в 14:30 · было на пт 23» — когда сделано и куда была поставлена.
    private func graveMeta(_ task: PlannerTask) -> String {
        var parts: [String] = []
        if let completed = task.completedAt {
            let minutes = DayMath.calendar.component(.hour, from: completed) * 60
                + DayMath.calendar.component(.minute, from: completed)
            parts.append("в " + ClockGrid.format(minutes: minutes))
        }
        if let day = task.day {
            parts.append("было на " + DayMath.label(offset: DayMath.offset(of: day)))
        } else {
            parts.append("из бэклога")
        }
        return parts.joined(separator: " · ")
    }

    private func stat(_ value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Tokens.caption)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 64)
        .background(Tokens.cluster, in: RoundedRectangle(cornerRadius: 14))
    }
}
