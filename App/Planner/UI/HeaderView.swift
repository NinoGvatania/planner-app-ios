import SwiftUI

enum ViewMode: String, CaseIterable, Identifiable {
    case day, threeDays, weekList, matrix

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: return "День"
        case .threeDays: return "3 дня"
        case .weekList: return "Неделя списком"
        case .matrix: return "Матрица Эйзенхауэра"
        }
    }

    var symbol: String {
        switch self {
        case .day: return "rectangle.portrait"
        case .threeDays: return "rectangle.split.3x1"
        case .weekList: return "list.bullet"
        case .matrix: return "square.grid.2x2"
        }
    }
}

/// Шапка: дата, «Просрочено · N», переключатель вида, «к сегодня».
struct HeaderView: View {
    let title: String
    let subtitle: String
    let overdueCount: Int
    let todayNumber: Int
    @Binding var mode: ViewMode
    @Binding var showDone: Bool
    let onOverdue: () -> Void
    let onToday: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 22, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(Tokens.caption)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if overdueCount > 0 {
                Button(action: onOverdue) {
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.system(size: 15, weight: .semibold))
                        Text("\(overdueCount)")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color(hex: 0x1A0706))
                            .frame(minWidth: 24, minHeight: 24)
                            .padding(.horizontal, 2)
                            .background(Tokens.overdueBadge, in: Capsule())
                    }
                    .padding(.leading, 12)
                    .padding(.trailing, 9)
                    .frame(height: Tokens.hitTarget)
                    .background(Tokens.overdueChip, in: Capsule())
                    .foregroundStyle(Tokens.overdue)
                }
                .accessibilityLabel("Просрочено: \(overdueCount)")
            }

            HStack(spacing: 0) {
                Menu {
                    Picker("Вид", selection: $mode) {
                        ForEach(ViewMode.allCases) { item in
                            Label(item.title, systemImage: item.symbol).tag(item)
                        }
                    }
                    Divider()
                    Toggle("Показывать выполненные", isOn: $showDone)
                } label: {
                    Image(systemName: mode.symbol)
                        .font(.system(size: 18, weight: .medium))
                        .frame(width: Tokens.hitTarget, height: Tokens.hitTarget)
                }
                .accessibilityLabel("Переключить вид")

                Button(action: onToday) {
                    ZStack {
                        Image(systemName: "calendar")
                            .font(.system(size: 19, weight: .medium))
                        Text("\(todayNumber)")
                            .font(.system(size: 8, weight: .bold))
                            .offset(y: 3)
                    }
                    .frame(width: Tokens.hitTarget, height: Tokens.hitTarget)
                }
                .accessibilityLabel("К сегодняшнему дню")
            }
            .padding(2)
            .background(Tokens.cluster, in: Capsule())
            .foregroundStyle(Tokens.text)
        }
        .padding(.leading, 18)
        .padding(.trailing, 12)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .frame(height: 62)
    }
}
