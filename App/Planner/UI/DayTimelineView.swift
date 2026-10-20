import PlannerCore
import SwiftUI

/// Строка «весь день» и сетка 0:00–24:00 одного дня.
struct DayTimelineView: View {
    let timed: [PlannerTask]
    let allDay: [PlannerTask]
    let showNow: Bool
    let onToggle: (PlannerTask) -> Void

    private let topInset: CGFloat = 10
    private let gridHeight = 24 * Tokens.hourHeight

    private var placements: [String: LanePlacement] {
        let items = timed.map { LayoutItem(id: $0.id.uuidString, start: $0.start ?? 0, duration: $0.duration) }
        var result: [String: LanePlacement] = [:]
        for placement in DayLayout.lanes(for: items) {
            result[placement.id] = placement
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            allDayRow
            Rectangle().fill(Tokens.line).frame(height: 1)
            GeometryReader { geometry in
                let areaWidth = max(0, geometry.size.width - Tokens.gutter - 8)
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        TimelineView(.everyMinute) { _ in
                            grid(areaWidth: areaWidth)
                        }
                    }
                    .onAppear {
                        let hour = max(0, min(23, DayMath.nowMinutes() / 60 - 1))
                        DispatchQueue.main.async {
                            proxy.scrollTo("hour-\(hour)", anchor: .top)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Весь день

    private var allDayRow: some View {
        HStack(alignment: .top, spacing: 0) {
            Text("весь\nдень")
                .font(.system(size: 11))
                .foregroundStyle(Tokens.muted)
                .multilineTextAlignment(.trailing)
                .frame(width: Tokens.gutter - 7, alignment: .trailing)
                .padding(.top, 9)
            VStack(spacing: 4) {
                ForEach(allDay, id: \.id) { task in
                    allDayChip(task)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .top)
            .padding(.horizontal, 3)
            .padding(.vertical, 6)
            .padding(.leading, 7)
            .overlay(alignment: .leading) { Rectangle().fill(Tokens.line).frame(width: 1) }
        }
        .padding(.trailing, 8)
    }

    private func allDayChip(_ task: PlannerTask) -> some View {
        let style = task.quadrant.style
        return HStack(spacing: 2) {
            Button { onToggle(task) } label: {
                Circle()
                    .strokeBorder(style.dot, lineWidth: 2)
                    .background(Circle().fill(task.isDone ? style.dot : Color.clear))
                    .frame(width: 13, height: 13)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
            .accessibilityLabel((task.isDone ? "Вернуть в работу: " : "Отметить выполненной: ") + task.title)
            Text(task.title)
                .font(.system(size: 12.5))
                .lineLimit(1)
                .strikethrough(task.isDone)
            Spacer(minLength: 0)
        }
        .padding(.leading, 1)
        .padding(.trailing, 8)
        .frame(height: 28)
        .foregroundStyle(style.text)
        .background(style.background, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(style.border, lineWidth: 1))
        .opacity(task.isDone ? 0.55 : 1)
    }

    // MARK: - Сетка

    private func grid(areaWidth: CGFloat) -> some View {
        let nowMinutes = DayMath.nowMinutes()
        let nowTop = topInset + CGFloat(nowMinutes) / 60 * Tokens.hourHeight
        return ZStack(alignment: .topLeading) {
            // Часы: настоящие строки по 56 pt, чтобы прокрутка к часу работала.
            VStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { hour in
                    let top = topInset + CGFloat(hour) * Tokens.hourHeight
                    hourRow(hour, hideLabel: showNow && abs(top - nowTop) < 22)
                        .frame(height: Tokens.hourHeight)
                        .id("hour-\(hour)")
                }
            }
            .padding(.top, topInset)
            .padding(.bottom, 26)

            Rectangle()
                .fill(Tokens.line)
                .frame(width: 1, height: gridHeight)
                .position(x: Tokens.gutter + 0.5, y: topInset + gridHeight / 2)

            ForEach(timed, id: \.id) { task in
                if let placement = placements[task.id.uuidString] {
                    let laneWidth = areaWidth / CGFloat(placement.laneCount)
                    let width = max(0, laneWidth - 6)
                    let top = topInset + CGFloat(task.start ?? 0) / 60 * Tokens.hourHeight + 1
                    let height = max(CGFloat(task.duration) / 60 * Tokens.hourHeight - 2, 24)
                    TaskBlockView(
                        task: task,
                        height: height,
                        compact: laneWidth < 160,
                        onToggle: { onToggle(task) }
                    )
                    .frame(width: width, height: height)
                    .position(
                        x: Tokens.gutter + laneWidth * CGFloat(placement.lane) + 3 + width / 2,
                        y: top + height / 2
                    )
                }
            }

            if showNow {
                nowLine(minutes: nowMinutes, areaWidth: areaWidth)
                    .position(x: (Tokens.gutter + 8 + areaWidth) / 2, y: nowTop)
                    .allowsHitTesting(false)
            }
        }
        .padding(.trailing, 8)
    }

    private func hourRow(_ hour: Int, hideLabel: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Tokens.line)
                .frame(height: 1)
                .padding(.leading, Tokens.gutter)
            Text("\(hour):00")
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(Tokens.muted)
                .frame(width: Tokens.gutter - 8, alignment: .trailing)
                .offset(y: -7)
                .opacity(hideLabel ? 0 : 1)
        }
    }

    private func nowLine(minutes: Int, areaWidth: CGFloat) -> some View {
        HStack(spacing: 0) {
            Text(ClockGrid.format(minutes: minutes))
                .font(.system(size: 11, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Tokens.accent)
                .frame(width: Tokens.gutter - 4, alignment: .trailing)
            ZStack(alignment: .leading) {
                Rectangle().fill(Tokens.accent).frame(height: 2)
                Circle().fill(Tokens.accent).frame(width: 10, height: 10).offset(x: -1)
            }
            .padding(.leading, 4)
        }
        .frame(width: Tokens.gutter + 8 + areaWidth, height: 12)
    }
}
