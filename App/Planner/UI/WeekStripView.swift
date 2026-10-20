import SwiftUI

/// Полоска недели: 7 вкладок начиная с сегодняшнего дня.
struct WeekStripView: View {
    @Binding var dayOffset: Int
    let hasTasks: (Int) -> Bool

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { offset in
                let date = DayMath.day(offset: offset)
                let selected = offset == dayOffset
                Button {
                    dayOffset = offset
                } label: {
                    VStack(spacing: 3) {
                        Text(DayMath.weekdayShort[DayMath.weekdayIndex(date)])
                            .font(.system(size: 11))
                            .foregroundStyle(selected ? Tokens.onAccent : Tokens.muted)
                        Text("\(DayMath.dayOfMonth(date))")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(selected ? Tokens.onAccent : (offset == 0 ? Tokens.accent : Tokens.text))
                        Circle()
                            .fill(hasTasks(offset) ? (selected ? Tokens.onAccent : Color(hex: 0x5A5B63)) : Color.clear)
                            .frame(width: 4, height: 4)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(selected ? Tokens.accent : Color.clear, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(DayMath.accessibilityLabel(offset: offset))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 2)
        .padding(.bottom, 6)
    }
}
