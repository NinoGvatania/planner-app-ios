import SwiftUI

/// Полоска недели: 7 вкладок начиная с сегодняшнего дня. Каждая вкладка — зона сброса.
struct WeekStripView: View {
    @Binding var dayOffset: Int
    /// Первый день полоски: сегодня, либо понедельник недели выбранного дня, если он дальше недели.
    var start: Int = 0
    let hasTasks: (Int) -> Bool
    /// Вкладка, над которой сейчас держат перетаскиваемую задачу.
    var hoveredOffset: Int? = nil

    var body: some View {
        HStack(spacing: 4) {
            ForEach(start..<(start + 7), id: \.self) { offset in
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
                .reportZone("tab-\(offset)")
                .accessibilityLabel(DayMath.accessibilityLabel(offset: offset))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 2)
        .padding(.bottom, 6)
        .animation(.easeOut(duration: 0.15), value: hoveredOffset)
    }
}
