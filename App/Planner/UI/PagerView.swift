import SwiftUI

/// Горизонтальный пейджер «как у месяца»: соседние страницы отрисованы рядом, страница едет за пальцем,
/// отпустили — доезжает и подменяется без скачка. Жесты и зоны сброса живут только на средней странице.
struct PagerView<Content: View>: View {
    @Binding var index: Int
    /// Листать нельзя прямо сейчас (задачу держат, тянут ручку): проверяется в момент жеста.
    var blocked: () -> Bool = { false }
    /// Станет `true` посреди свайпа (взяли задачу) — страница возвращается на место.
    var cancelWhen = false
    /// Разовый «подскок» при первом показе — намёк, что листается; по ключу один раз за запуск.
    var hintKey: String? = nil
    @ViewBuilder let content: (_ index: Int, _ live: Bool, _ syncTick: Int) -> Content

    @State private var dragX: CGFloat = 0
    @State private var axis: Axis?
    @State private var width: CGFloat = 0
    /// Растёт в начале горизонтального свайпа: соседние страницы подравнивают прокрутку под среднюю.
    @State private var syncTick = 0

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            HStack(spacing: 0) {
                content(index - 1, false, syncTick)
                    .frame(width: size.width, height: size.height)
                    .allowsHitTesting(false)
                content(index, true, syncTick)
                    .frame(width: size.width, height: size.height)
                content(index + 1, false, syncTick)
                    .frame(width: size.width, height: size.height)
                    .allowsHitTesting(false)
            }
            .offset(x: -size.width + dragX)
            .onChange(of: size.width, initial: true) { _, value in width = value }
        }
        .clipped()
        .simultaneousGesture(swipe)
        .onChange(of: cancelWhen) { _, cancel in
            if cancel { settleBack() }
        }
        .task { await hintOnce() }
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                if axis == nil {
                    let horizontal = abs(value.translation.width) > abs(value.translation.height) * 1.3
                    axis = horizontal && !blocked() ? .horizontal : .vertical
                    if axis == .horizontal { syncTick += 1 }
                }
                guard axis == .horizontal, !blocked() else { return }
                dragX = value.translation.width
            }
            .onEnded { value in
                let wasHorizontal = axis == .horizontal
                axis = nil
                guard wasHorizontal, width > 0, !blocked() else {
                    settleBack()
                    return
                }
                let projected = value.predictedEndTranslation.width
                if abs(value.translation.width) > width * 0.2 || abs(projected) > width * 0.45 {
                    let direction = value.translation.width < 0 ? 1 : -1
                    withAnimation(.easeOut(duration: 0.22)) {
                        dragX = -CGFloat(direction) * width
                    } completion: {
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            index += direction
                            dragX = 0
                        }
                    }
                } else {
                    settleBack()
                }
            }
    }

    private func settleBack() {
        axis = nil
        guard dragX != 0 else { return }
        withAnimation(.easeOut(duration: 0.2)) { dragX = 0 }
    }

    private func hintOnce() async {
        guard let hintKey, !PagerHint.shown.contains(hintKey) else { return }
        PagerHint.shown.insert(hintKey)
        try? await Task.sleep(for: .seconds(0.5))
        guard dragX == 0, axis == nil, !blocked() else { return }
        withAnimation(.easeInOut(duration: 0.28)) { dragX = -36 }
        try? await Task.sleep(for: .seconds(0.32))
        withAnimation(.spring(duration: 0.4, bounce: 0.3)) { dragX = 0 }
    }
}

/// Намёк на свайп показывается один раз за запуск на каждый ключ.
@MainActor
enum PagerHint {
    static var shown: Set<String> = []
}
