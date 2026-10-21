import Charts
import PlannerCore
import SwiftData
import SwiftUI

/// Диаграмма: круговая диаграмма времени по проектам за показанный период, под ней — легенда.
/// Считается запланированное время задач с датой в периоде (вместе с рутинами и сделанными).
/// Период и листание — у экрана (заголовок-меню и свайп), здесь только задачи этого периода.
struct DashboardView: View {
    let tasks: [PlannerTask]
    let onOpenProjects: () -> Void

    private struct Slice: Identifiable {
        let id: String
        let name: String
        let minutes: Int
        let count: Int
        let done: Int
        let color: Color
    }

    @Query(sort: \Project.name) private var projects: [Project]

    private var slices: [Slice] {
        var byName: [String?: (minutes: Int, count: Int, done: Int)] = [:]
        for task in tasks where task.day != nil {
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

    var body: some View {
        let slices = slices
        let total = slices.reduce(0) { $0 + $1.minutes }
        ScrollView(showsIndicators: false) {
            VStack(spacing: 14) {
                chart(slices, total: total)
                    .frame(height: 230)
                    .padding(.top, 10)
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
