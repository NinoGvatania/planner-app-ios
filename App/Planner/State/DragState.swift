import Foundation
import SwiftUI

/// Куда сейчас можно бросить перетаскиваемую задачу.
enum DropTarget: Equatable {
    case backlog
    case dayTab(offset: Int)
    case allDay
    case grid(start: Int)
    case quadrant(Int)
}

/// Текущее перетаскивание: что тянем и где палец (в координатах экрана «planner»).
struct DragState: Equatable {
    var taskID: UUID
    var title: String
    var duration: Int
    var location: CGPoint
    /// Насколько ниже верха блока схватили (для блоков сетки), иначе — половина высоты, но не больше 20 pt.
    var grabOffsetY: CGFloat
    var fromTimeline: Bool
    var target: DropTarget?
}

/// Рамки зон сброса в координатах «planner», собираются через PreferenceKey.
struct ZoneFramesKey: PreferenceKey {
    static var defaultValue: [String: CGRect] { [:] }
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Сообщает рамку этого вида в координатном пространстве «planner».
    func reportZone(_ id: String) -> some View {
        background(
            GeometryReader { geometry in
                Color.clear.preference(key: ZoneFramesKey.self, value: [id: geometry.frame(in: .named("planner"))])
            }
        )
    }
}
