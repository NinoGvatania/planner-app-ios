import SwiftUI

/// Полоска недели с понедельника: 7 вкладок, каждая — зона сброса. Листается свайпом как страницы:
/// выбранный день переезжает на тот же день соседней недели. Выбранный день — капля «жидкого стекла»:
/// при тапе она перетекает к новому дню.
/// Дни нажимаются тапом, а не кнопкой: кнопка срабатывала, когда палец отпускали после свайпа
/// (страница едет вместе с пальцем), и выбор улетал на день, с которого начали листать.
struct WeekStripView: View {
    @Binding var dayOffset: Int
    let hasTasks: (Int) -> Bool
    /// Вкладка, над которой сейчас держат перетаскиваемую задачу.
    var hoveredOffset: Int? = nil
    var blocked: () -> Bool = { false }

    @Namespace private var glass
    /// Выделенный день на экране. Отдельно от `dayOffset`: тап двигает выделение пружиной, а сетку дня
    /// переключает без анимации (иначе сетка «проваливалась» через тёмный кадр).
    @State private var shownDay: Int?

    private var selectedDay: Int { shownDay ?? dayOffset }

    /// Понедельник текущей недели — точка отсчёта страниц.
    private var baseMonday: Int { DayMath.weekStartOffset(containing: 0) }

    private var weekIndex: Binding<Int> {
        Binding(
            get: { (DayMath.weekStartOffset(containing: dayOffset) - baseMonday) / 7 },
            set: { index in
                let weekday = dayOffset - DayMath.weekStartOffset(containing: dayOffset)
                dayOffset = baseMonday + index * 7 + weekday
            }
        )
    }

    var body: some View {
        PagerView(index: weekIndex, blocked: blocked) { index, live, _ in
            week(baseMonday + index * 7, live: live)
        }
        .frame(height: 64)
        .animation(.easeOut(duration: 0.15), value: hoveredOffset)
        .onChange(of: dayOffset) { _, value in
            // День сменился не тапом (листание недели, «сегодня», «пружина» при переносе): выделение
            // встаёт туда же — с анимацией изменения, если она была; при листании недели — без неё.
            if shownDay != value { shownDay = value }
        }
    }

    private func select(_ offset: Int) {
        guard offset != dayOffset else { return }
        withAnimation(.spring(duration: 0.4, bounce: 0.22)) { shownDay = offset }
        dayOffset = offset
    }

    /// Одна страница недели. Зоны сброса сообщает только видимая (`live`), чтобы соседние не спорили.
    private func week(_ first: Int, live: Bool) -> some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 4) {
                ForEach(first..<(first + 7), id: \.self) { offset in
                    dayTab(offset, live: live)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 2)
        .padding(.bottom, 6)
    }

    private func dayTab(_ offset: Int, live: Bool) -> some View {
        let date = DayMath.day(offset: offset)
        let selected = offset == selectedDay
        let hovered = hoveredOffset == offset && !selected
        return VStack(spacing: 3) {
            Text(DayMath.weekdayShort[DayMath.weekdayIndex(date)])
                .font(.system(size: 11))
                .foregroundStyle(selected ? Tokens.onAccent : Tokens.muted)
            Text("\(DayMath.dayOfMonth(date))")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(selected ? Tokens.onAccent : (offset == 0 ? Tokens.accent : (offset < 0 ? Tokens.muted : Tokens.text)))
            Circle()
                .fill(hasTasks(offset) ? (selected ? Tokens.onAccent : Color(hex: 0x5A5B63)) : Color.clear)
                .frame(width: 4, height: 4)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .background {
            if selected {
                // Стеклянная капля выбранного дня: одна на полоску, при смене дня перетекает.
                Color.clear
                    .glassEffect(.regular.tint(Tokens.accent.opacity(0.85)), in: RoundedRectangle(cornerRadius: 14))
                    .glassEffectID("selected-day", in: glass)
            } else if hovered {
                RoundedRectangle(cornerRadius: 14).fill(Tokens.accent.opacity(0.22))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { select(offset) }
        .reportZone("tab-\(offset)", enabled: live)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DayMath.accessibilityLabel(offset: offset))
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : [.isButton])
        .accessibilityAction { select(offset) }
        .accessibilityHidden(!live)
    }
}
