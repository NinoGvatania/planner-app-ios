import Foundation
import SwiftUI

/// Куда сейчас можно бросить перетаскиваемую задачу.
enum DropTarget: Equatable {
    case backlog
    case dayTab(offset: Int)
    case allDay(day: Int)
    case grid(day: Int, start: Int)
    case quadrant(Int)
    /// Проект по названию; `nil` — «Без проекта».
    case project(String?)
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
    /// Сообщает рамку этого вида в координатном пространстве «planner» (или другом названном).
    /// `enabled: false` оставляет GeometryReader на месте, но ничего не сообщает — для зон внутри
    /// ScrollView, чьи рамки иначе меняются на каждом кадре прокрутки и перерисовывают экран.
    func reportZone(_ id: String, space: String = "planner", enabled: Bool = true) -> some View {
        background(
            GeometryReader { geometry in
                Color.clear.preference(
                    key: ZoneFramesKey.self,
                    value: enabled ? [id: geometry.frame(in: .named(space))] : [:]
                )
            }
        )
    }
}

/// Где начало пространства «planner» в координатах окна. Обычный класс: пишется из геометрии вида вне List,
/// читается жестом в момент касания, перерисовки не нужны.
final class PlannerOrigin {
    var point: CGPoint = .zero
}

extension View {
    /// Запоминать начало пространства «planner» в координатах окна по рамке этого вида (он должен быть
    /// вне List, чтобы его геометрия была свежей).
    func trackPlannerOrigin(_ origin: PlannerOrigin) -> some View {
        onGeometryChange(for: CGPoint.self) { proxy in
            let global = proxy.frame(in: .global)
            let planner = proxy.frame(in: .named("planner"))
            return CGPoint(x: global.minX - planner.minX, y: global.minY - planner.minY)
        } action: { point in
            origin.point = point
        }
    }
}

/// Страница пейджера просит не листать: внутри открыт список со свайпами строк и т. п.
/// Обычный класс: читается в момент жеста, перерисовки не нужны.
final class PagingLock {
    var locked = false
}

/// Смещение прокрутки сетки. Обычный класс, не Observable: меняется на каждом кадре прокрутки,
/// и перерисовывать экран из-за этого не нужно; читается в момент жеста.
final class GridScroll {
    var offset: CGFloat = 0
    /// Идёт растягивание ручкой или создание удержанием: свайп между днями в это время не работает.
    var interacting = false
}
