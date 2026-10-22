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

    @Environment(\.scenePhase) private var scenePhase
    @State private var dragX: CGFloat = 0
    @State private var axis: Axis?
    @State private var width: CGFloat = 0
    /// Растёт в начале горизонтального свайпа: соседние страницы подравнивают прокрутку под среднюю.
    @State private var syncTick = 0
    /// Страница ещё доезжает после прошлого свайпа или намёка: обычный класс, читается только из жеста.
    @State private var motion = PagerMotion()

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            HStack(spacing: 0) {
                content(index - 1, false, syncTick)
                    .frame(width: size.width, height: size.height)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                content(index, true, syncTick)
                    .frame(width: size.width, height: size.height)
                content(index + 1, false, syncTick)
                    .frame(width: size.width, height: size.height)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .offset(x: -size.width + dragX)
            .onChange(of: size.width, initial: true) { _, value in width = value }
        }
        .clipped()
        .simultaneousGesture(swipe)
        .onChange(of: cancelWhen) { _, cancel in
            if cancel { settleBack() }
        }
        .onChange(of: scenePhase) { _, phase in
            // Звонок или уход в фон посреди свайпа: конца жеста не будет — вернуть страницу на место.
            if phase != .active { settleBack() }
        }
        .task(id: hintKey) { await hintOnce() }
    }

    private var swipe: some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                if axis == nil {
                    let horizontal = abs(value.translation.width) > abs(value.translation.height) * 1.3
                    axis = horizontal && !blocked() ? .horizontal : .vertical
                    if axis == .horizontal {
                        syncTick += 1
                        // Палец пришёл, пока страница ещё доезжала: присвоить смещение сразу — значит
                        // оборвать анимацию и дёрнуть страницу. Такой свайп догоняет палец пружиной.
                        motion.catchingUp = Date() < motion.settleUntil
                    }
                }
                guard axis == .horizontal, !blocked() else { return }
                if motion.catchingUp {
                    withAnimation(.interactiveSpring(response: 0.16, dampingFraction: 0.9)) {
                        dragX = value.translation.width
                    }
                } else {
                    dragX = value.translation.width
                }
            }
            .onEnded { value in
                let wasHorizontal = axis == .horizontal
                axis = nil
                motion.catchingUp = false
                guard wasHorizontal, width > 0, !blocked() else {
                    settleBack()
                    return
                }
                let projected = value.predictedEndTranslation.width
                if abs(value.translation.width) > width * 0.2 || abs(projected) > width * 0.45 {
                    let direction = value.translation.width < 0 ? 1 : -1
                    // Страница подменяется сразу (картинка не меняется: сдвиг компенсируется), потом доезжает.
                    // Так второй быстрый свайп не застаёт незавершённую подмену. Если период упёрся
                    // в край и номер не изменился — просто вернуться.
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    let before = index
                    withTransaction(transaction) {
                        index += direction
                        if index != before { dragX += CGFloat(direction) * width }
                    }
                    motion.settleUntil = Date().addingTimeInterval(0.22)
                    withAnimation(.easeOut(duration: 0.22)) { dragX = 0 }
                } else {
                    settleBack()
                }
            }
    }

    private func settleBack() {
        axis = nil
        motion.catchingUp = false
        guard dragX != 0 else { return }
        motion.settleUntil = Date().addingTimeInterval(0.2)
        withAnimation(.easeOut(duration: 0.2)) { dragX = 0 }
    }

    /// Подскок на 36 pt и обратно. Ушли с экрана раньше — намёк не тратится и не дёргает другую страницу;
    /// палец успел взяться за страницу — возврат не делается, страницей уже управляет свайп.
    private func hintOnce() async {
        guard let hintKey, !PagerHint.shown.contains(hintKey) else { return }
        try? await Task.sleep(for: .seconds(0.5))
        guard !Task.isCancelled, dragX == 0, axis == nil, !blocked() else { return }
        PagerHint.shown.insert(hintKey)
        motion.settleUntil = Date().addingTimeInterval(1.0)
        withAnimation(.easeInOut(duration: 0.28)) { dragX = -36 }
        try? await Task.sleep(for: .seconds(0.32))
        // Даже если задачу отменили (сменили режим), страницу нужно вернуть на место.
        guard axis == nil else { return }
        withAnimation(.spring(duration: 0.4, bounce: 0.3)) { dragX = 0 }
    }
}

/// Доезд страницы после свайпа: до какого момента он идёт и догоняет ли текущий свайп палец пружиной.
/// Обычный класс, не Observable: читается только из жеста, перерисовки не нужны.
final class PagerMotion {
    var settleUntil = Date.distantPast
    var catchingUp = false
}

/// Намёк на свайп показывается один раз за запуск на каждый ключ.
@MainActor
enum PagerHint {
    static var shown: Set<String> = []
}
