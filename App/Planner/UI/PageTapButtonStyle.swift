import SwiftUI

/// Кнопка внутри листаемой страницы пейджера: срабатывает только от настоящего тапа.
/// Обычная кнопка срабатывает, если палец отпустили над ней. А страница при свайпе едет вместе с пальцем,
/// поэтому кнопка, с которой начали свайп, «нажималась» сама: день в полоске недели возвращал выбор
/// туда, где коснулись, галочка отмечала задачу сделанной, секция сворачивалась. Жест тапа после
/// протягивания пальца не срабатывает, а короткий бросок, который тап ещё пропускает, отсекает `onPageTap`.
struct PageTapButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PageTapButton(configuration: configuration)
    }
}

/// Отдельный вид, чтобы прочитать `isEnabled`: выключенная кнопка (`.disabled`) не срабатывает.
private struct PageTapButton: View {
    let configuration: PrimitiveButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .contentShape(Rectangle())
            .onPageTap {
                if isEnabled { configuration.trigger() }
            }
    }
}

extension PrimitiveButtonStyle where Self == PageTapButtonStyle {
    /// Кнопка листаемой страницы: только тап, протягивание пальца её не нажимает.
    static var pageTap: PageTapButtonStyle { PageTapButtonStyle() }
}
