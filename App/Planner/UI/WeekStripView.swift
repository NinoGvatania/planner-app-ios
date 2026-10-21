import SwiftUI

/// Полоска недели с понедельника: 7 вкладок, каждая — зона сброса. Свайп влево/вправо листает недели —
/// полоска едет за пальцем, выбранный день переезжает на тот же день следующей/прошлой недели.
struct WeekStripView: View {
    @Binding var dayOffset: Int
    /// Понедельник показанной недели.
    var start: Int = 0
    let hasTasks: (Int) -> Bool
    /// Вкладка, над которой сейчас держат перетаскиваемую задачу.
    var hoveredOffset: Int? = nil
    /// Пользователь пролистнул полоску: +1 — следующая неделя, −1 — прошлая.
    var onShiftWeek: ((Int) -> Void)? = nil

    @State private var dragX: CGFloat = 0
    @State private var axis: Axis?

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            HStack(spacing: 0) {
                week(start - 7, width: width, live: false)
                week(start, width: width, live: true)
                week(start + 7, width: width, live: false)
            }
            .offset(x: -width + dragX)
            .simultaneousGesture(swipe(width: width))
        }
        .frame(height: 64)
        .clipped()
        .animation(.easeOut(duration: 0.15), value: hoveredOffset)
    }

    private func swipe(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                if axis == nil {
                    axis = abs(value.translation.width) > abs(value.translation.height) * 1.3 ? .horizontal : .vertical
                }
                guard axis == .horizontal else { return }
                dragX = value.translation.width
            }
            .onEnded { value in
                let wasHorizontal = axis == .horizontal
                axis = nil
                guard wasHorizontal, width > 0 else { return }
                let projected = value.predictedEndTranslation.width
                if abs(value.translation.width) > width * 0.2 || abs(projected) > width * 0.45 {
                    let direction = value.translation.width < 0 ? 1 : -1
                    withAnimation(.easeOut(duration: 0.2)) {
                        dragX = -CGFloat(direction) * width
                    } completion: {
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            onShiftWeek?(direction)
                            dragX = 0
                        }
                    }
                } else {
                    withAnimation(.easeOut(duration: 0.2)) { dragX = 0 }
                }
            }
    }

    /// Одна страница недели. Зоны сброса сообщает только видимая (`live`), чтобы соседние не спорили.
    private func week(_ first: Int, width: CGFloat, live: Bool) -> some View {
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
        .frame(width: width)
    }
}
