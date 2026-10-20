import SwiftData
import SwiftUI

@main
struct PlannerApp: App {
    var body: some Scene {
        WindowGroup {
            PlannerScreen()
                .preferredColorScheme(.dark)
        }
        .modelContainer(for: [PlannerTask.self, Project.self, Routine.self])
    }
}
