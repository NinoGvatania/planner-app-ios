import Foundation

/// Сетка дня: минуты ↔ точки, шаг 15 минут, формат времени и длительности.
public enum ClockGrid {
    /// Высота часа в точках, как в прототипе.
    public static let pointsPerHour: Double = 56
    public static let dayStart = 0
    public static let dayEnd = 24 * 60
    public static let step = 15

    public static func points(forMinutes minutes: Int) -> Double {
        Double(minutes) / 60 * pointsPerHour
    }

    public static func minutes(forPoints points: Double) -> Int {
        Int((points / pointsPerHour * 60).rounded())
    }

    /// Ближайшая четверть часа.
    public static func snapped(_ minutes: Int) -> Int {
        Int((Double(minutes) / Double(step)).rounded()) * step
    }

    /// Начало, при котором задача целиком помещается в день.
    public static func clampedStart(_ start: Int, duration: Int) -> Int {
        max(dayStart, min(start, dayEnd - duration))
    }

    /// «9:05», «14:30», конец дня — «24:00».
    public static func format(minutes: Int) -> String {
        if minutes == dayEnd { return "24:00" }
        let h = (minutes / 60) % 24
        let m = minutes % 60
        return "\(h):" + (m < 10 ? "0\(m)" : "\(m)")
    }

    /// «45 мин», «1 ч», «1 ч 30 мин».
    public static func formatDuration(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) мин" }
        let h = minutes / 60
        let m = minutes % 60
        return m == 0 ? "\(h) ч" : "\(h) ч \(m) мин"
    }
}
