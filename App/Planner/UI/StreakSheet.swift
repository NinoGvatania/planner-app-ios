import SwiftUI

/// Лист серии: огонёк, дни подряд, неделя точками, лучшая серия.
struct StreakSheet: View {
    let info: Streak.Info
    @Environment(\.dismiss) private var dismiss

    private let flame = Color(hex: 0xFF9F43)
    private var dayLetters: [String] { ["пн", "вт", "ср", "чт", "пт", "сб", "вс"] }
    private var todayIndex: Int { (DayMath.weekdayIndex(DayMath.today()) + 6) % 7 }

    private var headline: String {
        switch info.current {
        case 0: return "Серия не начата"
        default: return "\(info.current) " + DayMath.plural(info.current, "день", "дня", "дней") + " подряд"
        }
    }

    private var hint: String {
        if info.current == 0 { return "Сделай сегодня хотя бы одну задачу — и серия начнётся." }
        if info.todayClosed { return "Сегодня уже закрыто: сделано \(info.todayDone) " + DayMath.plural(info.todayDone, "задача", "задачи", "задач") + ". Так держать!" }
        return "Сегодня ещё ничего не сделано — закрой хотя бы одну задачу, чтобы серия не прервалась."
    }

    var body: some View {
        VStack(spacing: 18) {
            Capsule()
                .fill(Color(hex: 0x3A3B41))
                .frame(width: 38, height: 5)
                .padding(.top, 8)
            Image(systemName: info.current > 0 ? "flame.fill" : "flame")
                .font(.system(size: 64, weight: .bold))
                .foregroundStyle(info.current > 0 ? flame : Tokens.muted)
                .shadow(color: info.current > 0 ? flame.opacity(0.55) : .clear, radius: 24)
                .padding(.top, 6)
            Text(headline)
                .font(.system(size: 24, weight: .bold))
            Text(hint)
                .font(.system(size: 14))
                .foregroundStyle(Tokens.caption)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
            HStack(spacing: 10) {
                ForEach(0..<7, id: \.self) { index in
                    let closed = info.week[index]
                    VStack(spacing: 6) {
                        ZStack {
                            Circle()
                                .fill(closed ? flame : Tokens.cluster)
                                .frame(width: 34, height: 34)
                            if closed {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 14, weight: .heavy))
                                    .foregroundStyle(Color(hex: 0x2A1200))
                            } else if index == todayIndex {
                                Circle().strokeBorder(flame, lineWidth: 2).frame(width: 34, height: 34)
                            }
                        }
                        Text(dayLetters[index])
                            .font(.system(size: 11, weight: index == todayIndex ? .bold : .regular))
                            .foregroundStyle(index == todayIndex ? Tokens.text : Tokens.muted)
                    }
                }
            }
            .padding(.top, 6)
            HStack(spacing: 10) {
                stat("\(info.best)", label: "лучшая серия")
                stat("\(info.todayDone)", label: "сделано сегодня")
            }
            .padding(.horizontal, 20)
            Spacer(minLength: 0)
            Button {
                dismiss()
            } label: {
                Text("Готово")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Tokens.onAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Tokens.accent, in: RoundedRectangle(cornerRadius: 14))
                    .contentShape(Rectangle())
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
        .foregroundStyle(Tokens.text)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Tokens.panel)
        .presentationDetents([.fraction(0.72), .large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(Tokens.panel)
    }

    private func stat(_ value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(size: 22, weight: .bold))
                .monospacedDigit()
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Tokens.caption)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 64)
        .background(Tokens.cluster, in: RoundedRectangle(cornerRadius: 14))
    }
}
