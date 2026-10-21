import Charts
import PlannerCore
import SwiftData
import SwiftUI

/// Дашборд: круговая диаграмма времени по проектам за день, неделю, месяц или год, под ней — легенда.
/// Считается запланированное время задач с датой в периоде (вместе с рутинами и сделанными).
struct DashboardView: View {
    let tasks: [PlannerTask]
    let onOpenProjects: () -> Void

    enum Period: String, CaseIterable, Identifiable {
        case day, week, month, year
        var id: String { rawValue }
        var title: String {
            switch self {
            case .day: return "День"
            case .week: return "Неделя"
            case .month: return "Месяц"
            case .year: return "Год"
            }
        }
    }

    private struct Slice: Identifiable {
        let id: String
        let name: String
        let minutes: Int
        let count: Int
        let done: Int
        let color: Color
    }

    @AppStorage("dashboardPeriod") private var periodRaw = Period.week.rawValue
    /// Сдвиг периода от текущего: −1 — прошлый, +1 — следующий.
    @State private var shift = 0
    @Query(sort: \Project.name) private var projects: [Project]

    private var period: Period { Period(rawValue: periodRaw) ?? .week }

    /// Границы периода: [start, end).
    private var range: (start: Date, end: Date) {
        let cal = DayMath.calendar
        let today = DayMath.today()
        switch period {
        case .day:
            let start = cal.date(byAdding: .day, value: shift, to: today) ?? today
            return (start, cal.date(byAdding: .day, value: 1, to: start) ?? start)
        case .week:
            let monday = DayMath.day(offset: DayMath.weekStartOffset(containing: 0) + shift * 7)
            return (monday, cal.date(byAdding: .day, value: 7, to: monday) ?? monday)
        case .month:
            let start = DayMath.date(DayMath.monthStart(of: today), addingMonths: shift)
            return (start, DayMath.date(start, addingMonths: 1))
        case .year:
            let year = DayMath.year(today) + shift
            let start = cal.date(from: DateComponents(year: year, month: 1, day: 1)) ?? today
            return (start, cal.date(byAdding: .year, value: 1, to: start) ?? start)
        }
    }

    private var rangeTitle: String {
        let (start, end) = range
        let last = DayMath.calendar.date(byAdding: .day, value: -1, to: end) ?? start
        switch period {
        case .day:
            return DayMath.title(offset: DayMath.offset(of: start))
        case .week:
            return DayMath.monthIndex(start) == DayMath.monthIndex(last)
                ? "\(DayMath.dayOfMonth(start))–\(DayMath.dayOfMonth(last)) \(DayMath.monthShort[DayMath.monthIndex(start)])"
                : "\(DayMath.dayOfMonth(start)) \(DayMath.monthShort[DayMath.monthIndex(start)]) – \(DayMath.dayOfMonth(last)) \(DayMath.monthShort[DayMath.monthIndex(last)])"
        case .month:
            return DayMath.monthNominative[DayMath.monthIndex(start)] + " \(DayMath.year(start))"
        case .year:
            return "\(DayMath.year(start))"
        }
    }

    private var inRange: [PlannerTask] {
        let (start, end) = range
        return tasks.filter { task in
            guard let day = task.day else { return false }
            return day >= start && day < end
        }
    }

    private var slices: [Slice] {
        var byName: [String?: (minutes: Int, count: Int, done: Int)] = [:]
        for task in inRange {
            var entry = byName[task.project?.name] ?? (0, 0, 0)
            entry.minutes += task.duration
            entry.count += 1
            if task.isDone { entry.done += 1 }
            byName[task.project?.name] = entry
        }
        let colors = Dictionary(projects.map { ($0.name, $0.color) }, uniquingKeysWith: { first, _ in first })
        return byName
            .map { name, entry in
                Slice(id: name ?? "", name: name ?? "Без проекта", minutes: entry.minutes, count: entry.count, done: entry.done,
                      color: name.flatMap { colors[$0] } ?? QuadrantStyle.unsorted.dot)
            }
            .sorted { a, b in
                if a.minutes != b.minutes { return a.minutes > b.minutes }
                return a.name < b.name
            }
    }

    private var totalMinutes: Int { slices.reduce(0) { $0 + $1.minutes } }

    var body: some View {
        let slices = slices
        let total = totalMinutes
        VStack(spacing: 0) {
            Picker("Период", selection: $periodRaw) {
                ForEach(Period.allCases) { item in
                    Text(item.title).tag(item.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 14)
            .onChange(of: periodRaw) { _, _ in shift = 0 }

            HStack(spacing: 0) {
                periodButton("chevron.left", label: "Прошлый период") { shift -= 1 }
                // Заголовок периода; если период сдвинут, весь центр — кнопка «к текущему» (цель ≥ 44 pt).
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { shift = 0 }
                } label: {
                    VStack(spacing: 2) {
                        Text(rangeTitle)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundStyle(Tokens.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        if shift != 0 {
                            Text("К текущему")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Tokens.accent)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: Tokens.hitTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(shift == 0)
                .accessibilityLabel(shift == 0 ? rangeTitle : rangeTitle + ". Вернуться к текущему периоду")
                periodButton("chevron.right", label: "Следующий период") { shift += 1 }
            }
            .padding(.horizontal, 6)
            .frame(height: 52)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    chart(slices, total: total)
                        .frame(height: 230)
                        .padding(.top, 4)
                    if slices.isEmpty {
                        Text("За этот период задач с датой нет")
                            .font(.system(size: 14))
                            .foregroundStyle(Tokens.caption)
                            .padding(.top, 8)
                    } else {
                        legend(slices, total: total)
                    }
                    Button(action: onOpenProjects) {
                        Label("Проекты…", systemImage: "folder")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(Tokens.caption)
                            .frame(maxWidth: .infinity, minHeight: Tokens.hitTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 16)
            }
        }
        .animation(.easeOut(duration: 0.25), value: periodRaw)
        .animation(.easeOut(duration: 0.25), value: shift)
    }

    private func periodButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) { action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Tokens.text)
                .frame(width: Tokens.hitTarget, height: Tokens.hitTarget)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }

    private func chart(_ slices: [Slice], total: Int) -> some View {
        ZStack {
            if slices.isEmpty {
                Circle()
                    .strokeBorder(Tokens.cluster, lineWidth: 34)
                    .padding(26)
            } else {
                Chart(slices) { slice in
                    SectorMark(
                        angle: .value("Минуты", slice.minutes),
                        innerRadius: .ratio(0.64),
                        angularInset: 1.5
                    )
                    .cornerRadius(5)
                    .foregroundStyle(slice.color)
                }
                .chartLegend(.hidden)
            }
            VStack(spacing: 2) {
                Text(total == 0 ? "0" : hoursText(total))
                    .font(.system(size: 26, weight: .bold))
                    .monospacedDigit()
                Text(total == 0 ? "ничего не запланировано" : (slices.count == 1 ? "1 проект" : "\(slices.count) " + DayMath.plural(slices.count, "проект", "проекта", "проектов")))
                    .font(.system(size: 12))
                    .foregroundStyle(Tokens.caption)
            }
            .frame(maxWidth: 120)
            .multilineTextAlignment(.center)
        }
    }

    private func legend(_ slices: [Slice], total: Int) -> some View {
        VStack(spacing: 6) {
            ForEach(slices) { slice in
                let percent = total == 0 ? 0 : Int((Double(slice.minutes) / Double(total) * 100).rounded())
                HStack(spacing: 10) {
                    Circle().fill(slice.color).frame(width: 12, height: 12)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(slice.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(slice.id.isEmpty ? Tokens.caption : Tokens.text)
                            .lineLimit(1)
                        Text(hoursText(slice.minutes) + " · \(slice.count) " + DayMath.plural(slice.count, "задача", "задачи", "задач") + (slice.done > 0 ? ", сделано \(slice.done)" : ""))
                            .font(.system(size: 12))
                            .foregroundStyle(Tokens.caption)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Text("\(percent)%")
                        .font(.system(size: 15, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(slice.color)
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 52)
                .background(Tokens.panel, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.06), lineWidth: 1))
            }
        }
    }

    /// «3 ч 30 м», «45 м», «12 ч».
    private func hoursText(_ minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        if hours == 0 { return "\(rest) м" }
        return rest == 0 ? "\(hours) ч" : "\(hours) ч \(rest) м"
    }
}
