import Foundation
import SwiftData

/// Проект — метка для группировки со своим цветом. Цвет задачи берётся из квадранта
/// или из проекта — по настройке «Цвет задач» (см. `ColorMode`).
@Model
final class Project {
    @Attribute(.unique) var name: String
    /// Индекс в палитре `ProjectPalette.colors`.
    var colorIndex: Int = 0
    @Relationship(deleteRule: .nullify, inverse: \PlannerTask.project) var tasks: [PlannerTask]

    init(name: String, colorIndex: Int = 0) {
        self.name = name
        self.colorIndex = colorIndex
        self.tasks = []
    }
}
