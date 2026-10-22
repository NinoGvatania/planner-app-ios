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
    /// разными пружинами — линза вытягивается в сторону движения и подтягивается, как капля. Каждый край
    /// анимирует свой модификатор (`LensEdges`): у одного вида рамка одна, и две пружины на ней слились бы.
    @State private var lensFrom: CGFloat
    @State private var lensTo: CGFloat
    @State private var width: CGFloat = 0
    /// Поднятая линза; `nil` — линза лежит.
    @GestureState private var lensHold: LensHold? = nil
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
            if lensHold == nil { moveLens(to: Self.weekday(of: value)) }
        }
        .onChange(of: lensHold) { old, new in
            lensLock.held = new != nil
            if let new {
                followFinger(new.x, previous: old?.x)
            } else {
                settleLens()
            }
        }
        // Щелчок, когда линзу подняли, на каждом новом дне под ней и когда отпустили.
        .sensoryFeedback(.selection, trigger: lensHold == nil ? nil : dayOffset)
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

    /// Поднятая линза идёт за пальцем (тоже с вытягиванием). День под ней открывается, когда её центр
    /// ушёл за середину соседнего дня с запасом: на границе двух дней выбор не дребезжит.
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
        let current = Self.weekday(of: dayOffset)
        if abs(edge - CGFloat(current)) > 0.62 {
            open(slot: Int(edge.rounded()))
        }
    }

    /// Отпустили (или жест сорвался): линза садится на ближайший день.
    private func settleLens() {
        let nearest = min(6, max(0, Int(lensFrom.rounded())))
        if nearest != Self.weekday(of: dayOffset) {
            open(slot: nearest)
        } else {
            moveLens(to: nearest)
        }
    }

    /// Открыть день недели `slot` той же недели. Пока линзу держат, сама линза за этим не едет.
    private func open(slot: Int) {
        let target = DayMath.weekStartOffset(containing: dayOffset) + min(6, max(0, slot))
        if target != dayOffset { dayOffset = target }
    }

    /// Удержание на выбранном дне поднимает линзу, дальше она идёт за пальцем — за ту точку, за которую
    /// её взяли: центр запоминается в момент подъёма.
    private func lensGesture(weekday: Int) -> some Gesture {
        let restCenter = metrics.center(weekday)
        return LongPressGesture(minimumDuration: 0.25)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.pageSpace)))
            .updating($lensHold) { value, state, _ in
                guard case .second(true, let drag) = value else { return }
                let grabbed = state?.grabbed ?? restCenter
                state = LensHold(grabbed: grabbed, x: grabbed + (drag?.translation.width ?? 0))
            }
    }

    // MARK: - Страница

    private static let pageSpace = "week-strip-page"

    /// Одна страница недели. Зоны сброса сообщает только видимая (`live`), чтобы соседние не спорили,
    /// и только пока тянут задачу. Линза есть на каждой странице на том же дне недели: при листании
    /// недели она приезжает вместе с новой неделей, а не появляется после.
    private func week(_ first: Int, live: Bool) -> some View {
        let weekday = Self.weekday(of: dayOffset)
        // Точки «есть задачи» — один раз на страницу: подписи рисуются дважды (обычные и на линзе).
        let dots = (0..<7).map { hasTasks(first + $0) }
        let lifted = lensHold != nil
        return ZStack(alignment: .topLeading) {
            HStack(spacing: StripMetrics.spacing) {
                ForEach(0..<7, id: \.self) { index in
                    dayTab(first + index, hasDot: dots[index], live: live)
                }
            }
            .padding(.horizontal, StripMetrics.inset)
            // Под стеклом светлых подписей нет — только фон: иначе они просвечивали бы рядом с тёмными.
            .mask {
                Color.clear.modifier(LensEdges(from: lensFrom, to: lensTo) { from, to in
                    lensHole(from: from, to: to, lifted: lifted)
                })
            }

            Color.clear
                .modifier(LensEdges(from: lensFrom, to: lensTo) { from, to in
                    lens(first: first, dots: dots, from: from, to: to, lifted: lifted)
                })
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

    private static let lensShape = RoundedRectangle(cornerRadius: 14, style: .continuous)
    /// Пружина подъёма линзы: она чуть больше и сплющена, как капля под пальцем.
    private static let liftSpring = Animation.spring(response: 0.3, dampingFraction: 0.62)

    /// Стеклянная линза с краями `from`…`to`. Тёмные подписи — содержимое самого стекла, поэтому стекло
    /// всегда под ними (стекло, нарисованное отдельным слоем, закрывало число). Подписи сдвинуты на левый
    /// край линзы, чтобы стоять ровно над своими днями и «проявляться», когда линза над ними проезжает.
    private func lens(first: Int, dots: [Bool], from: CGFloat, to: CGFloat, lifted: Bool) -> some View {
        let m = metrics
        let left = m.left(from)
        return Color.clear
            .overlay(alignment: .leading) {
                HStack(spacing: StripMetrics.spacing) {
                    ForEach(0..<7, id: \.self) { index in
                        tabLabel(first + index, hasDot: dots[index], onLens: true)
                    }
                }
                .padding(.horizontal, StripMetrics.inset)
                .frame(width: m.width, height: 56)
                .offset(x: -left)
            }
            .frame(width: max(0, m.right(to) - left), height: 56)
            .clipShape(Self.lensShape)
            .animation(Self.liftSpring) { content in
                content
                    .glassEffect(.regular.tint(Tokens.accent.opacity(lifted ? 0.72 : 0.85)), in: Self.lensShape)
                    .scaleEffect(x: lifted ? 1.14 : 1, y: lifted ? 1.06 : 1)
            }
            .offset(x: left)
            .opacity(m.slot > 0 ? 1 : 0)
    }

    /// Маска обычных подписей: всё, кроме места линзы (с тем же подъёмом).
    private func lensHole(from: CGFloat, to: CGFloat, lifted: Bool) -> some View {
        let m = metrics
        let left = m.left(from)
        return Rectangle()
            .overlay(alignment: .topLeading) {
                Self.lensShape
                    .frame(width: max(0, m.right(to) - left), height: 56)
                    .animation(Self.liftSpring) { content in
                        content.scaleEffect(x: lifted ? 1.14 : 1, y: lifted ? 1.06 : 1)
                    }
                    .offset(x: left)
                    .blendMode(.destinationOut)
                    .opacity(m.slot > 0 ? 1 : 0)
            }
            .compositingGroup()
    }

    private func dayTab(_ offset: Int, hasDot: Bool, live: Bool) -> some View {
        let selected = offset == dayOffset
        let hovered = hoveredOffset == offset && !selected
        return tabLabel(offset, hasDot: hasDot, onLens: false)
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
    private func tabLabel(_ offset: Int, hasDot: Bool, onLens: Bool) -> some View {
        let date = DayMath.day(offset: offset)
        return VStack(spacing: 3) {
            Text(DayMath.weekdayShort[DayMath.weekdayIndex(date)])
                .font(.system(size: 11))
                .foregroundStyle(onLens ? Tokens.onAccent
                                 : (DayMath.isWeekend(date) ? Tokens.weekend.opacity(offset < 0 ? 0.5 : 0.8) : Tokens.muted))
            Text("\(DayMath.dayOfMonth(date))")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(onLens ? Tokens.onAccent
                                 : (offset == 0 ? Tokens.accent
                                    : Tokens.dayNumber(isToday: false, isWeekend: DayMath.isWeekend(date), isPast: offset < 0)))
            Circle()
                .fill(hasDot ? (onLens ? Tokens.onAccent : Color(hex: 0x5A5B63)) : Color.clear)
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

    /// Левый край для левого края линзы `edge` (в ширинах вкладки).
    func left(_ edge: CGFloat) -> CGFloat { Self.inset + edge * step }
    /// Правый край для правого края линзы `edge`.
    func right(_ edge: CGFloat) -> CGFloat { Self.inset + edge * step - Self.spacing }
    func center(_ weekday: Int) -> CGFloat { Self.inset + CGFloat(weekday) * step + slot / 2 }
    /// Левый край линзы с центром в `x`.
    func edge(atCenter x: CGFloat) -> CGFloat { step > 0 ? (x - Self.inset - slot / 2) / step : 0 }
}

/// Края линзы, каждый со своим аниматором: левый анимирует этот модификатор, правый — вложенный.
/// Так пружины краёв не сливаются, и линза вытягивается. `lens` получает уже промежуточные края.
private struct LensEdges<Lens: View>: ViewModifier, Animatable {
    var from: CGFloat
    let to: CGFloat
    let lens: (_ from: CGFloat, _ to: CGFloat) -> Lens

    nonisolated var animatableData: CGFloat {
        get { from }
        set { from = newValue }
    }

    func body(content: Content) -> some View {
        content.modifier(LensTrailingEdge(from: from, to: to, lens: lens))
    }
}

private struct LensTrailingEdge<Lens: View>: ViewModifier, Animatable {
    let from: CGFloat
    var to: CGFloat
    let lens: (_ from: CGFloat, _ to: CGFloat) -> Lens

    nonisolated var animatableData: CGFloat {
        get { to }
        set { to = newValue }
    }

    func body(content: Content) -> some View {
        content.overlay(alignment: .topLeading) { lens(from, to) }
    }
}

/// Поднятая линза: центр под пальцем в момент подъёма и текущий центр.
private struct LensHold: Equatable {
    var grabbed: CGFloat
    var x: CGFloat
}

/// Линзу держат пальцем. Обычный класс: пейджер спрашивает его из жеста, перерисовки не нужны.
private final class LensLock {
    var held = false
}
