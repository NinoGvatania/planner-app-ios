import SwiftUI
import UIKit

/// Удержание ~0,3 с и затем перетаскивание — через UIKit-распознаватель. Внутри ScrollView он не мешает
/// прокрутке: движение до срабатывания — прокрутка, после — перенос (в отличие от связки
/// LongPressGesture + DragGesture, которая в iOS 18+ перехватывает скролл). Координаты — в названном
/// пространстве `space`.
struct HoldDragGesture: UIGestureRecognizerRepresentable {
    var space: String = "planner"
    var minimumDuration: TimeInterval = 0.3
    /// (где палец, где палец был в момент срабатывания).
    var onChanged: (CGPoint, CGPoint) -> Void
    var onEnded: () -> Void
    /// Система отменила жест (звонок, уход в фон): состояние сбрасывается, сброс не считается.
    var onCancelled: (() -> Void)? = nil

    final class Coordinator: NSObject {
        var start: CGPoint = .zero
        let haptic = UIImpactFeedbackGenerator(style: .medium)
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = minimumDuration
        recognizer.allowableMovement = 12
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        let location = context.converter.location(in: .named(space))
        switch recognizer.state {
        case .began:
            context.coordinator.start = location
            context.coordinator.haptic.impactOccurred()
            onChanged(location, location)
        case .changed:
            onChanged(location, context.coordinator.start)
        case .ended:
            onEnded()
        case .cancelled, .failed:
            (onCancelled ?? onEnded)()
        default:
            break
        }
    }
}
