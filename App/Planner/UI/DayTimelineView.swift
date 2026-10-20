import PlannerCore
import SwiftUI

/// Строка «весь день» и сетка 0:00–24:00 одного дня.
/// Тап по блоку выделяет его, ручка снизу растягивает, удержание начинает перетаскивание.
struct DayTimelineView: View {
    let timed: [PlannerTask]
    let allDay: [PlannerTask]
    let showNow: Bool
    @Binding var selectedID: UUID?
    let drag: DragState?
    let onToggle: (PlannerTask) -> Void
    let onResize: (PlannerTask, Int) -> Void
    /// (задача, где палец, где палец был в начале) в координатах «planner».
    let onDragChanged: (PlannerTask, CGPoint, CGPoint) -> Void
    let onDragEnded: () -> Void
    /// Создать задачу на свободном месте: (начало, длительность) в минутах.
    let onCreate: (Int, Int) -> Void

    @State private var liveDuration: Int?
    /// Силуэт создаваемой задачи, пока тянут по свободному месту: (начало, длительность).
    @State private var creating: (start: Int, duration: Int)?

    private let topInset: CGFloat = 10
    private let gridHeight = 24 * Tokens.hourHeight

    private func duration(of task: PlannerTask) -> Int {
        task.id == selectedID ? (liveDuration ?? task.duration) : task.duration
    }

    private var placements: [String: LanePlacement] {
        let items = timed.map { LayoutItem(id: $0.id.uuidString, start: $0.start ?? 0, duration: duration(of: $0)) }
        var result: [String: LanePlacement] = [:]
        for placement in DayLayout.lanes(for: items) {
            result[placement.id] = placement
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            allDayRow
                .reportZone("allday")
            Rectangle().fill(Tokens.line).frame(height: 1)
            GeometryReader { geometry in
                let areaWidth = max(0, geometry.size.width - Tokens.gutter - 8)
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        TimelineView(.everyMinute) { _ in
                            grid(areaWidth: areaWidth)
                        }
                        .reportZone("grid")
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
        let hovered = drag?.target == .allDay
        return HStack(alignment: .top, spacing: 0) {
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
            .background(hovered ? Tokens.accent.opacity(0.14) : Color.clear)
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
        .opacity(drag?.taskID == task.id ? 0.35 : (task.isDone ? 0.55 : 1))
        .contentShape(Rectangle())
        .gesture(dragGesture(for: task))
    }

    // MARK: - Сетка

    private func grid(areaWidth: CGFloat) -> some View {
        let nowMinutes = DayMath.nowMinutes()
        let nowTop = topInset + CGFloat(nowMinutes) / 60 * Tokens.hourHeight
        return ZStack(alignment: .topLeading) {
            // Свободное место: тап создаёт задачу (или снимает выделение), удержание с протягиванием — задачу нужной длины.
            Color.clear
                .frame(height: topInset + gridHeight + 26)
                .contentShape(Rectangle())
                .onTapGesture(count: 1) { location in
                    if selectedID != nil {
                        selectedID = nil
                        liveDuration = nil
                    } else {
                        let start = snappedMinutes(forY: location.y)
                        onCreate(ClockGrid.clampedStart(start, duration: 30), 30)
                    }
                }
                .gesture(
                    LongPressGesture(minimumDuration: 0.3)
                        .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("grid")))
                        .onChanged { value in
                            if case .second(true, let dragValue?) = value {
                                let start = snappedMinutes(forY: dragValue.startLocation.y)
                                let end = snappedMinutes(forY: dragValue.location.y)
                                let duration = max(15, min(end - start, ClockGrid.dayEnd - start))
                                creating = (start: ClockGrid.clampedStart(start, duration: duration), duration: duration)
                            }
                        }
                        .onEnded { _ in
                            if let creating = creating {
                                onCreate(creating.start, creating.duration)
                            }
                            creating = nil
                        }
                )

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
            .allowsHitTesting(false)

            Rectangle()
                .fill(Tokens.line)
                .frame(width: 1, height: gridHeight)
                .position(x: Tokens.gutter + 0.5, y: topInset + gridHeight / 2)

            ForEach(timed, id: \.id) { task in
                if let placement = placements[task.id.uuidString] {
                    block(task, placement: placement, areaWidth: areaWidth)
                }
            }

            if let drag = drag, case .grid(let start) = drag.target {
                let height = max(CGFloat(drag.duration) / 60 * Tokens.hourHeight - 2, 24)
                let top = topInset + CGFloat(start) / 60 * Tokens.hourHeight + 1
                dropPreview(start: start, duration: drag.duration)
                    .frame(width: areaWidth - 6, height: height)
                    .position(x: Tokens.gutter + 3 + (areaWidth - 6) / 2, y: top + height / 2)
                    .allowsHitTesting(false)
            }

            if let creating = creating {
                let height = max(CGFloat(creating.duration) / 60 * Tokens.hourHeight - 2, 24)
                let top = topInset + CGFloat(creating.start) / 60 * Tokens.hourHeight + 1
                dropPreview(start: creating.start, duration: creating.duration)
                    .frame(width: areaWidth - 6, height: height)
                    .position(x: Tokens.gutter + 3 + (areaWidth - 6) / 2, y: top + height / 2)
                    .allowsHitTesting(false)
            }

            if showNow {
                nowLine(minutes: nowMinutes, areaWidth: areaWidth)
                    .position(x: (Tokens.gutter + 8 + areaWidth) / 2, y: nowTop)
                    .allowsHitTesting(false)
            }
        }
        .padding(.trailing, 8)
        .coordinateSpace(name: "grid")
    }

    private func block(_ task: PlannerTask, placement: LanePlacement, areaWidth: CGFloat) -> some View {
        let laneWidth = areaWidth / CGFloat(placement.laneCount)
        let width = max(0, laneWidth - 6)
        let start = task.start ?? 0
        let dur = duration(of: task)
        let top = topInset + CGFloat(start) / 60 * Tokens.hourHeight + 1
        let height = max(CGFloat(dur) / 60 * Tokens.hourHeight - 2, 24)
        let selected = task.id == selectedID && drag == nil
        let left = Tokens.gutter + laneWidth * CGFloat(placement.lane) + 3
        return ZStack(alignment: .topLeading) {
            TaskBlockView(
                task: task,
                height: height,
                compact: laneWidth < 160,
                selected: selected,
                liveDuration: selected ? liveDuration : nil,
                dimmed: drag?.taskID == task.id,
                onToggle: { onToggle(task) }
            )
            .frame(width: width, height: height)
            .position(x: left + width / 2, y: top + height / 2)
            .zIndex(selected ? 2 : 1)
            .onTapGesture {
                selectedID = selectedID == task.id ? nil : task.id
                liveDuration = nil
            }
            .gesture(dragGesture(for: task))

            if selected {
                resizeHandle(task, start: start, top: top, height: height, centerX: left + width / 2)
                    .zIndex(3)
            }
        }
    }

    private func resizeHandle(_ task: PlannerTask, start: Int, top: CGFloat, height: CGFloat, centerX: CGFloat) -> some View {
        Capsule()
            .fill(Color.white)
            .frame(width: 44, height: 6)
            .overlay(Capsule().stroke(Tokens.background, lineWidth: 2))
            .frame(width: 88, height: 40)
            .contentShape(Rectangle())
            .position(x: centerX, y: top + height)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .named("grid"))
                    .onChanged { value in
                        let bottom = value.location.y - topInset
                        let minutes = Int((bottom / Tokens.hourHeight * 60 / 15).rounded()) * 15
                        let newDuration = max(15, min(minutes - start, ClockGrid.dayEnd - start))
                        if newDuration != liveDuration { liveDuration = newDuration }
                    }
                    .onEnded { _ in
                        if let value = liveDuration, value != task.duration {
                            onResize(task, value)
                        }
                        liveDuration = nil
                    }
            )
            .accessibilityHidden(true)
    }

    private func dragGesture(for task: PlannerTask) -> some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("planner")))
            .onChanged { value in
                if case .second(true, let dragValue?) = value {
                    onDragChanged(task, dragValue.location, dragValue.startLocation)
                }
            }
            .onEnded { _ in onDragEnded() }
    }

    private func dropPreview(start: Int, duration: Int) -> some View {
        RoundedRectangle(cornerRadius: 9)
            .fill(Tokens.accent.opacity(0.14))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                    .foregroundStyle(Tokens.accent)
            )
            .overlay(alignment: .topLeading) {
                Text(ClockGrid.format(minutes: start) + "–" + ClockGrid.format(minutes: start + duration))
                    .font(.system(size: 12, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(Tokens.accent)
                    .padding(.horizontal, 8)
                    .padding(.top, 3)
            }
    }

    /// Минуты от 0:00 по вертикальной координате в сетке, с шагом 15 минут.
    private func snappedMinutes(forY y: CGFloat) -> Int {
        let minutes = Int(((y - topInset) / Tokens.hourHeight * 60 / 15).rounded(.down)) * 15
        return max(0, min(ClockGrid.dayEnd, minutes))
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
