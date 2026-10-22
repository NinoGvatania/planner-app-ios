import PlannerCore
import SwiftUI

/// Список задач за период: секции по дням (день, неделя, месяц) или по месяцам (год), секции сворачиваются.
/// Секция дня — зона сброса: задача переезжает на этот день, время сохраняется.
struct PeriodListView: View {
    let tasks: [PlannerTask]
    let range: (start: Date, end: Date)
    let period: Period
    let drag: DragState?
    var live = true
    let onToggle: (PlannerTask) -> Void
    let onDragChanged: (PlannerTask, CGPoint, CGPoint) -> Void
    let onDragEnded: () -> Void
    let onEdit: (PlannerTask) -> Void
    var onDragCancelled: (() -> Void)? = nil

    @State private var collapsed: Set<String> = []

    private struct Section: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        /// Смещение дня для зоны сброса; `nil` — секция месяца.
        let dayOffset: Int?
        let items: [PlannerTask]
    }

    private var sections: [Section] {
        let cal = DayMath.calendar
        let today = DayMath.today()
        let inRange = tasks.filter { task in
            guard let day = task.day else { return false }
            return day >= range.start && day < range.end
        }
        func sorted(_ list: [PlannerTask]) -> [PlannerTask] {
            list.sorted { a, b in
                let da = a.day ?? today, db = b.day ?? today
                if da != db { return da < db }
                return (a.start ?? -1) < (b.start ?? -1)
            }
        }
        if period == .year {
            var result: [Section] = []
            var cursor = range.start
            while cursor < range.end {
                let next = DayMath.date(cursor, addingMonths: 1)
                let items = sorted(inRange.filter { ($0.day ?? today) >= cursor && ($0.day ?? today) < next })
                if !items.isEmpty {
                    result.append(Section(id: "m\(DayMath.monthIndex(cursor))", title: DayMath.monthNominative[DayMath.monthIndex(cursor)],
                                          subtitle: "\(items.count) " + DayMath.plural(items.count, "задача", "задачи", "задач"), dayOffset: nil, items: items))
                }
                cursor = next
            }
            return result
        }
        var result: [Section] = []
        var cursor = range.start
        let showEmpty = period == .day || period == .week
        while cursor < range.end {
            let offset = DayMath.offset(of: cursor)
            let items = sorted(inRange.filter { $0.day == cursor })
            if !items.isEmpty || showEmpty || offset == 0 {
                let title = offset == 0 ? "Сегодня" : (offset == 1 ? "Завтра" : (offset == -1 ? "Вчера" : DayMath.weekdayFull[DayMath.weekdayIndex(cursor)].capitalizedFirst))
                result.append(Section(id: "d\(offset)", title: title,
                                      subtitle: "\(DayMath.dayOfMonth(cursor)) \(DayMath.monthGenitive[DayMath.monthIndex(cursor)])", dayOffset: offset, items: items))
            }
            cursor = cal.date(byAdding: .day, value: 1, to: cursor) ?? range.end
        }
        return result
    }

    var body: some View {
        let sections = sections
        ScrollView(showsIndicators: false) {
            VStack(spacing: 10) {
                ForEach(sections) { section in
                    self.section(section)
                }
                if sections.isEmpty {
                    Text("За этот период задач нет")
                        .font(.system(size: 14))
                        .foregroundStyle(Tokens.caption)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
    }

    private func section(_ section: Section) -> some View {
        let isCollapsed = collapsed.contains(section.id)
        let hovered = section.dayOffset.map { drag?.target == .dayTab(offset: $0) } ?? false
        return VStack(spacing: 0) {
            Button {
                withAnimation(.spring(duration: 0.28)) {
                    if isCollapsed { collapsed.remove(section.id) } else { collapsed.insert(section.id) }
                }
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(section.title)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(section.dayOffset == 0 ? Tokens.accent : Tokens.text)
                    Text(section.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Tokens.muted)
                    Spacer()
                    if !section.items.isEmpty {
                        Text("\(section.items.count)")
                            .font(.system(size: 12, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Tokens.caption)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Tokens.caption)
                        .rotationEffect(.degrees(isCollapsed ? -90 : 0))
                }
                .padding(.horizontal, 8)
                .frame(minHeight: Tokens.hitTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pageTap)
            .accessibilityLabel((isCollapsed ? "Развернуть: " : "Свернуть: ") + section.title)
            if !isCollapsed {
                ForEach(section.items, id: \.id) { task in
                    row(task, showDate: section.dayOffset == nil)
                }
                if section.items.isEmpty {
                    Text("Свободно — перетащи сюда задачу")
                        .font(.system(size: 13))
                        .foregroundStyle(Tokens.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 10)
                        .padding(.top, 2)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 4)
        // При сворачивании гаснущие строки не вылезают из секции на соседнюю.
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .background(hovered ? Tokens.accent.opacity(0.12) : Color(hex: 0x141518), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(hovered ? Tokens.accent : Color.white.opacity(0.05), lineWidth: 1))
        // Секции лежат в ScrollView: рамки сообщаются только во время перетаскивания.
        .reportZone("tab-\(section.dayOffset ?? Int.min)", enabled: live && drag != nil && section.dayOffset != nil)
    }

    private func row(_ task: PlannerTask, showDate: Bool) -> some View {
        let style = task.style
        let when: String = {
            let time = task.start.map { ClockGrid.format(minutes: $0) } ?? "день"
            guard showDate, let day = task.day else { return time }
            return "\(DayMath.dayOfMonth(day)) \(DayMath.monthShort[DayMath.monthIndex(day)]) · " + time
        }()
        return HStack(spacing: 2) {
            Text(when)
                .font(.system(size: 12.5))
                .monospacedDigit()
                .foregroundStyle(Tokens.caption)
                .frame(width: showDate ? 96 : 54, alignment: .leading)
                .padding(.leading, 8)
            Button { onToggle(task) } label: {
                ZStack {
                    Circle()
                        .strokeBorder(style.dot, lineWidth: 2)
                        .background(Circle().fill(task.isDone ? style.dot : Color.clear))
                        .frame(width: 20, height: 20)
                    if task.isDone {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(Tokens.background)
                    }
                }
                .frame(width: Tokens.hitTarget, height: Tokens.hitTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.pageTap)
            .accessibilityLabel((task.isDone ? "Вернуть в работу: " : "Отметить выполненной: ") + task.title)
            // Название до двух строк; место справа — только если у задачи есть проект.
            Text(task.title)
                .font(.system(size: 15))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .strikethrough(task.isDone)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let project = task.project?.name {
                Text(project)
                    .font(.system(size: 12))
                    .foregroundStyle(Tokens.muted)
                    .lineLimit(1)
                    .frame(maxWidth: 90, alignment: .trailing)
            }
            Color.clear.frame(width: 6)
        }
        .padding(.vertical, 4)
        .frame(minHeight: 46)
        .opacity(drag?.taskID == task.id ? 0.35 : (task.isDone ? 0.5 : 1))
        .contentShape(Rectangle())
        .onPageTap { onEdit(task) }
        .gesture(HoldDragGesture(onChanged: { location, start in onDragChanged(task, location, start) }, onEnded: onDragEnded, onCancelled: onDragCancelled ?? onDragEnded))
    }
}
