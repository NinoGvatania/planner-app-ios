import SwiftUI

/// Полоска недели с понедельника: 7 вкладок, каждая — зона сброса. Листается свайпом как страницы:
/// выбранный день переезжает на тот же день соседней недели.
struct WeekStripView: View {
    @Binding var dayOffset: Int
    let hasTasks: (Int) -> Bool
    /// Вкладка, над которой сейчас держат перетаскиваемую задачу.
    var hoveredOffset: Int? = nil
    var blocked: () -> Bool = { false }

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
    }

    /// Одна страница недели. Зоны сброса сообщает только видимая (`live`), чтобы соседние не спорили.
    private func week(_ first: Int, live: Bool) -> some View {
        HStack(spacing: 4) {
            ForEach(first..<(first + 7), id: \.self) { offset in
                let date = DayMath.day(offset: offset)
                let selected = offset == dayOffset
                let hovered = hoveredOffset == offset && !selected
                Button {
                    dayOffset = offset
                } label: {
                    VStack(spacing: 3) {
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
                    .background(
                        selected ? Tokens.accent : (hovered ? Tokens.accent.opacity(0.22) : Color.clear),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                }
                .buttonStyle(.plain)
                .reportZone("tab-\(offset)", enabled: live)
                .accessibilityLabel(DayMath.accessibilityLabel(offset: offset))
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityHidden(!live)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 2)
        .padding(.bottom, 6)
    }
}
