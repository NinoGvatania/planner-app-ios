import Foundation
import SwiftData

/// Проект — только метка для группировки; цвет задачи берётся из квадранта.
@Model
final class Project {
    @Attribute(.unique) var name: String
    @Relationship(deleteRule: .nullify, inverse: \PlannerTask.project) var tasks: [PlannerTask]

    init(name: String) {
        self.name = name
        self.tasks = []
    }
}
