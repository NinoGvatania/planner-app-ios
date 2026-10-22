import SwiftUI

/// Полоска недели с понедельника: 7 вкладок, каждая — зона сброса. Листается свайпом как страницы:
/// выбранный день переезжает на тот же день соседней недели.
/// Выбранный день — «линза» из жидкого стекла. При тапе она перетекает: передний край убегает к новому
/// дню, задний догоняет. Удержание на линзе поднимает её — её можно тащить по дням, день под ней сразу
/// открывается, отпустили — линза садится на ближайший день.
/// Дни нажимаются тапом, а не кнопкой: кнопка срабатывала, когда палец отпускали после свайпа
/// (страница едет вместе с пальцем), и выбор улетал на день, с которого начали листать.
struct WeekStripView: View {
    @Binding var dayOffset: Int
    let hasTasks: (Int) -> Bool
    /// Вкладка, над которой сейчас держат перетаскиваемую задачу.
    var hoveredOffset: Int? = nil
    var blocked: () -> Bool = { false }
    /// Задачу сейчас тянут: только тогда вкладки сообщают зоны сброса. Иначе рамки вкладок менялись бы
    /// с каждым движением пальца по полоске и перерисовывали весь экран.
    var dragging = false

    /// Края линзы в ширинах вкладки: левый и правый. В покое `lensTo == lensFrom + 1`. Края двигаются
    /// разными пружинами — так линза вытягивается в сторону движения и подтягивается, как капля.
    /// Каждый край задаёт свой отступ (`padding`), поэтому анимации краёв не сливаются в одну.
    @State private var lensFrom: CGFloat
    @State private var lensTo: CGFloat
    @State private var width: CGFloat = 0
    /// Центр поднятой линзы по горизонтали (в координатах страницы); `nil` — линза лежит.
    @GestureState private var lensFinger: CGFloat? = nil
    /// Линзу держат: пейджер в это время не листает. Обычный класс — читается из жеста пейджера.
    @State private var lensLock = LensLock()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(dayOffset: Binding<Int>, hasTasks: @escaping (Int) -> Bool, hoveredOffset: Int? = nil,
         blocked: @escaping () -> Bool = { false }, dragging: Bool = false) {
        _dayOffset = dayOffset
        self.hasTasks = hasTasks
        self.hoveredOffset = hoveredOffset
        self.blocked = blocked
        self.dragging = dragging
        let weekday = CGFloat(Self.weekday(of: dayOffset.wrappedValue))
        _lensFrom = State(initialValue: weekday)
        _lensTo = State(initialValue: weekday + 1)
    }

    /// Понедельник текущей недели — точка отсчёта страниц.
    private var baseMonday: Int { DayMath.weekStartOffset(containing: 0) }

    private var metrics: StripMetrics { StripMetrics(width: width) }

    private static func weekday(of offset: Int) -> Int {
        offset - DayMath.weekStartOffset(containing: offset)
    }

    private var weekIndex: Binding<Int> {
        Binding(
            get: { (DayMath.weekStartOffset(containing: dayOffset) - baseMonday) / 7 },
            set: { index in
                dayOffset = baseMonday + index * 7 + Self.weekday(of: dayOffset)
            }
        )
    }

    var body: some View {
        let lock = lensLock
        PagerView(index: weekIndex, blocked: { blocked() || lock.held }) { index, live, _ in
            week(baseMonday + index * 7, live: live)
        }
        .frame(height: 64)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .animation(.easeOut(duration: 0.15), value: hoveredOffset)
        .onChange(of: dayOffset) { _, value in
            // День сменился не линзой (тап, листание недели, «сегодня», «пружина» при переносе) —
            // линза перетекает туда же. При листании недели день недели тот же, и линза стоит.
            if lensFinger == nil { moveLens(to: Self.weekday(of: value)) }
        }
        .onChange(of: lensFinger) { old, new in
            lensLock.held = new != nil
            if let new {
                followFinger(new, previous: old)
            } else {
                moveLens(to: Self.weekday(of: dayOffset))
            }
        }
        // Щелчок, когда линзу подняли, на каждом новом дне под ней и когда отпустили.
        .sensoryFeedback(.selection, trigger: lensFinger == nil ? nil : dayOffset)
    }

    private func select(_ offset: Int) {
        // Нажимается только видимая неделя — неделя выбранного дня. День другой недели — запоздалый тап
        // со страницы, которую только что пролистали: он вернул бы полоску назад.
        guard offset != dayOffset,
              DayMath.weekStartOffset(containing: offset) == DayMath.weekStartOffset(containing: dayOffset) else { return }
        dayOffset = offset
    }

    // MARK: - Линза

    /// Перетечь на день недели `weekday`: край по ходу движения быстрее, задний — с запаздыванием.
    private func moveLens(to weekday: Int) {
        let target = CGFloat(weekday)
        guard target != lensFrom || target + 1 != lensTo else { return }
        if reduceMotion {
            withAnimation(.easeInOut(duration: 0.2)) {
                lensFrom = target
                lensTo = target + 1
            }
            return
        }
        let forward = target > lensFrom
        let lead = Animation.spring(response: 0.3, dampingFraction: 0.72)
        let trail = Animation.spring(response: 0.5, dampingFraction: 0.76)
        withAnimation(forward ? lead : trail) { lensTo = target + 1 }
        withAnimation(forward ? trail : lead) { lensFrom = target }
    }

    /// Поднятая линза идёт за пальцем (тоже с вытягиванием), день под её центром сразу открывается.
    private func followFinger(_ x: CGFloat, previous: CGFloat?) {
        let m = metrics
        guard m.slot > 0 else { return }
        let edge = m.edge(atCenter: min(max(x, m.center(0)), m.center(6)))
        if let previous {
            let forward = x >= previous
            let lead = Animation.interactiveSpring(response: 0.16, dampingFraction: 0.86)
            let trail = reduceMotion ? lead : Animation.interactiveSpring(response: 0.32, dampingFraction: 0.8)
            withAnimation(forward ? lead : trail) { lensTo = edge + 1 }
            withAnimation(forward ? trail : lead) { lensFrom = edge }
        }
        let slot = min(6, max(0, Int(edge.rounded())))
        let target = DayMath.weekStartOffset(containing: dayOffset) + slot
        if target != dayOffset { dayOffset = target }
    }

    /// Удержание на выбранном дне поднимает линзу, дальше она идёт за пальцем.
    private func lensGesture(weekday: Int) -> some Gesture {
        let m = metrics
        return LongPressGesture(minimumDuration: 0.25)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.pageSpace)))
            .updating($lensFinger) { value, state, _ in
                guard case .second(true, let drag) = value else { return }
                if let drag {
                    // Палец мог взять линзу не за середину — держим её за ту же точку.
                    let grabbedCenter = m.center(m.slot(at: drag.startLocation.x))
                    state = drag.location.x - (drag.startLocation.x - grabbedCenter)
                } else {
                    state = m.center(weekday)
                }
            }
    }

    // MARK: - Страница

    private static let pageSpace = "week-strip-page"

    /// Одна страница недели. Зоны сброса сообщает только видимая (`live`), чтобы соседние не спорили,
    /// и только пока тянут задачу. Линза есть на каждой странице на том же дне недели: при листании
    /// недели она приезжает вместе с новой неделей, а не появляется после.
    private func week(_ first: Int, live: Bool) -> some View {
        let weekday = Self.weekday(of: dayOffset)
        return ZStack(alignment: .topLeading) {
            HStack(spacing: StripMetrics.spacing) {
                ForEach(first..<(first + 7), id: \.self) { offset in
                    dayTab(offset, live: live)
                }
            }
            .padding(.horizontal, StripMetrics.inset)

            lens(first: first)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            if live {
                // Ручка линзы — над выбранным днём; тап по нему и так ничего не делает.
                Color.clear
                    .frame(width: metrics.slot, height: 56)
                    .contentShape(RoundedRectangle(cornerRadius: 14))
                    .gesture(lensGesture(weekday: weekday))
                    .padding(.leading, metrics.left(CGFloat(weekday)))
                    .accessibilityHidden(true)
            }
        }
        .frame(height: 56)
        .coordinateSpace(name: Self.pageSpace)
        .padding(.top, 2)
        .padding(.bottom, 6)
    }

    /// Стеклянная линза. Тёмные подписи дней — содержимое самого стекла, поэтому стекло всегда под ними
    /// (стекло, нарисованное отдельным слоем, закрывало число). Подписи сдвинуты на левый край линзы,
    /// чтобы стоять ровно над своими днями и «проявляться», когда линза над ними проезжает.
    private func lens(first: Int) -> some View {
        let m = metrics
        let lifted = lensFinger != nil
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return Color.clear
            .overlay(alignment: .leading) {
                HStack(spacing: StripMetrics.spacing) {
                    ForEach(first..<(first + 7), id: \.self) { offset in
                        tabLabel(offset, onLens: true)
                    }
                }
                .padding(.horizontal, StripMetrics.inset)
                .frame(width: m.width, height: 56)
                .offset(x: -m.left(lensFrom))
            }
            .clipShape(shape)
            .animation(.spring(response: 0.3, dampingFraction: 0.62)) { content in
                content
                    .glassEffect(.regular.tint(Tokens.accent.opacity(lifted ? 0.72 : 0.85)), in: shape)
                    // Поднятая линза чуть больше и сплющена, как капля под пальцем.
                    .scaleEffect(x: lifted ? 1.14 : 1, y: lifted ? 1.06 : 1)
            }
            .padding(.leading, m.left(lensFrom))
            .padding(.trailing, max(0, m.width - m.right(lensTo)))
            .frame(width: m.width, height: 56)
            .opacity(m.slot > 0 ? 1 : 0)
    }

    private func dayTab(_ offset: Int, live: Bool) -> some View {
        let selected = offset == dayOffset
        let hovered = hoveredOffset == offset && !selected
        return tabLabel(offset, onLens: false)
            .background {
                if hovered {
                    RoundedRectangle(cornerRadius: 14).fill(Tokens.accent.opacity(0.22))
                }
            }
            .contentShape(Rectangle())
            .onPageTap { select(offset) }
            .reportZone("tab-\(offset)", enabled: live && dragging)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(DayMath.accessibilityLabel(offset: offset))
            .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
            .accessibilityAction { select(offset) }
            .accessibilityHidden(!live)
    }

    /// Подписи вкладки: обычные или тёмные — для линзы.
    private func tabLabel(_ offset: Int, onLens: Bool) -> some View {
        let date = DayMath.day(offset: offset)
        return VStack(spacing: 3) {
            Text(DayMath.weekdayShort[DayMath.weekdayIndex(date)])
                .font(.system(size: 11))
                .foregroundStyle(onLens ? Tokens.onAccent : Tokens.muted)
            Text("\(DayMath.dayOfMonth(date))")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(onLens ? Tokens.onAccent : (offset == 0 ? Tokens.accent : (offset < 0 ? Tokens.muted : Tokens.text)))
            Circle()
                .fill(hasTasks(offset) ? (onLens ? Tokens.onAccent : Color(hex: 0x5A5B63)) : Color.clear)
                .frame(width: 4, height: 4)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 56)
    }
}

/// Раскладка вкладок полоски: отступы по краям 12, между вкладками 4, вкладки равной ширины.
private struct StripMetrics {
    static let inset: CGFloat = 12
    static let spacing: CGFloat = 4

    let width: CGFloat

    var slot: CGFloat { max(0, (width - 2 * Self.inset - 6 * Self.spacing) / 7) }
    private var step: CGFloat { slot + Self.spacing }

    /// Левый край для края линзы `edge` (в ширинах вкладки).
    func left(_ edge: CGFloat) -> CGFloat { Self.inset + edge * step }
    /// Правый край для правого края линзы `edge`.
    func right(_ edge: CGFloat) -> CGFloat { Self.inset + edge * step - Self.spacing }
    func center(_ weekday: Int) -> CGFloat { Self.inset + CGFloat(weekday) * step + slot / 2 }
    /// Левый край линзы с центром в `x`.
    func edge(atCenter x: CGFloat) -> CGFloat { step > 0 ? (x - Self.inset - slot / 2) / step : 0 }
    /// Вкладка под точкой `x`.
    func slot(at x: CGFloat) -> Int {
        guard step > 0 else { return 0 }
        return min(6, max(0, Int(((x - Self.inset + Self.spacing / 2) / step).rounded(.down))))
    }
}

/// Линзу держат пальцем. Обычный класс: пейджер спрашивает его из жеста, перерисовки не нужны.
private final class LensLock {
    var held = false
}
