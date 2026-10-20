import PlannerCore
import SwiftUI

/// Цвета и размеры из прототипа (docs/PLAN.md, «Дизайн‑токены»).
enum Tokens {
    static let background = Color(hex: 0x0E0F11)
    static let drawer = Color(hex: 0x17181B)
    static let panel = Color(hex: 0x1A1B1E)
    static let field = Color(hex: 0x24252A)
    static let cluster = Color(hex: 0x1F2024)
    static let badge = Color(hex: 0x2A2B30)
    static let text = Color(hex: 0xF3F4F6)
    static let caption = Color(hex: 0xA1A1AA)
    static let muted = Color(hex: 0x8B8B94)
    static let accent = Color(hex: 0x3EE0A6)
    static let onAccent = Color(hex: 0x05261A)
    static let overdue = Color(hex: 0xFF7A70)
    static let overdueBadge = Color(hex: 0xFF6159)
    static let overdueChip = Color(hex: 0x3A1D1B)
    static let line = Color.white.opacity(0.08)

    static let hourHeight: CGFloat = 56
    static let gutter: CGFloat = 52
    /// Заголовок 52 + строка ввода 60; отступ под индикатором «домой» добавляет система.
    static let drawerCollapsed: CGFloat = 112
    static let hitTarget: CGFloat = 44
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

struct QuadrantStyle {
    let dot: Color
    let background: Color
    let border: Color
    let text: Color
}

extension Quadrant {
    var style: QuadrantStyle {
        switch self {
        case .urgentImportant:
            return QuadrantStyle(dot: Color(hex: 0xFF6159), background: Color(hex: 0x3A1D1B), border: Color(hex: 0x5E2B27), text: Color(hex: 0xFFE1DE))
        case .important:
            return QuadrantStyle(dot: Color(hex: 0xFFC53D), background: Color(hex: 0x3A2E12), border: Color(hex: 0x5E4A1C), text: Color(hex: 0xFFF0C7))
        case .urgent:
            return QuadrantStyle(dot: Color(hex: 0x5E9EFF), background: Color(hex: 0x18263D), border: Color(hex: 0x284270), text: Color(hex: 0xDDE9FF))
        case .other:
            return QuadrantStyle(dot: Color(hex: 0x5CCB6E), background: Color(hex: 0x162B1C), border: Color(hex: 0x27502F), text: Color(hex: 0xD6F5DC))
        }
    }
}

extension QuadrantStyle {
    /// Неразобранная задача: квадрант ещё не выбран.
    static let unsorted = QuadrantStyle(dot: Color(hex: 0x8C8C96), background: Color(hex: 0x232429), border: Color(hex: 0x3A3B42), text: Color(hex: 0xE6E6EB))
}

extension PlannerTask {
    /// Цвет задачи: серый, пока квадрант не выбран, иначе цвет квадранта.
    var style: QuadrantStyle { sortedQuadrant?.style ?? .unsorted }
}
