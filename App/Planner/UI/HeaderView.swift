import SwiftUI

/// Период, который показывает экран. Переключается заголовком-меню и свайпами.
enum Period: String, CaseIterable, Identifiable {
    case day, week, month, year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: return "День"
        case .week: return "Неделя"
        case .month: return "Месяц"
        case .year: return "Год"
        }
    }

    var symbol: String {
        switch self {
        case .day: return "rectangle.portrait"
        case .week: return "rectangle.split.3x1"
        case .month: return "calendar"
        case .year: return "square.grid.3x3"
        }
    }
}

/// Как показывать задачи выбранного периода.
enum Display: String, CaseIterable, Identifiable {
    case calendar, list, matrix, projects, chart

    var id: String { rawValue }

    var title: String {
        switch self {
        case .calendar: return "Календарь"
        case .list: return "Список"
        case .matrix: return "Матрица Эйзенхауэра"
        case .projects: return "Проекты"
        case .chart: return "Диаграмма"
        }
    }

    var symbol: String {
        switch self {
        case .calendar: return "calendar"
        case .list: return "list.bullet"
        case .matrix: return "square.grid.2x2"
        case .projects: return "folder"
        case .chart: return "chart.pie"
        }
    }
}

/// Шапка: заголовок-меню периода (день / неделя / месяц / год), отдельная кнопка серии и капсула:
/// кнопка режима (календарь / список / матрица / проекты / диаграмма), меню «…», «к сегодня».
/// «Просрочено» живёт в заголовке панели бэклога.
struct HeaderView: View {
    let title: String
    let subtitle: String
    /// Подзаголовок покороче — для узких экранов, чтобы текст не мельчал ниже 11 pt.
    let shortSubtitle: String
    let streak: Int
    let todayNumber: Int
    @Binding var period: Period
    @Binding var display: Display
    @Binding var showDone: Bool
    @Binding var colorMode: ColorMode
    let onStreak: () -> Void
    let onToday: () -> Void
    let onProjects: () -> Void
    let onSettings: () -> Void

    private let flame = Color(hex: 0xFF9F43)

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            Menu {
                Picker("Период", selection: $period) {
                    ForEach(Period.allCases) { item in
                        Label(item.title, systemImage: item.symbol).tag(item)
                    }
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(title)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(Tokens.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Tokens.caption)
                    }
                    ViewThatFits(in: .horizontal) {
                        Text(subtitle)
                            .lineLimit(1)
                        Text(shortSubtitle)
                            .lineLimit(1)
                            .minimumScaleFactor(0.88)
                    }
                    .font(.system(size: 12.5))
                    .foregroundStyle(Tokens.caption)
                }
                .frame(maxWidth: .infinity, minHeight: Tokens.hitTarget, alignment: .leading)
                .contentShape(Rectangle())
            }
            .layoutPriority(1)
            .accessibilityLabel("Период: \(period.title). Выбрать другой")

            // Серия — отдельной стеклянной кнопкой, не в капсуле управления.
            Button(action: onStreak) {
                HStack(spacing: 2) {
                    Image(systemName: streak > 0 ? "flame.fill" : "flame")
                        .font(.system(size: 15, weight: .bold))
                    Text("\(streak)")
                        .font(.system(size: 13, weight: .bold))
                        .monospacedDigit()
                }
                .foregroundStyle(streak > 0 ? flame : Tokens.muted)
                .frame(minWidth: Tokens.hitTarget, minHeight: Tokens.hitTarget)
                .padding(.horizontal, 4)
                .contentShape(Capsule())
            }
            .glassEffect(.regular.tint(Tokens.cluster.opacity(0.6)), in: Capsule())
            .accessibilityLabel("Серия: \(streak) дней подряд. История выполненных")

            // Капсула управления: режим, «…», «сегодня».
            HStack(spacing: 0) {
                Menu {
                    Picker("Вид", selection: $display) {
                        ForEach(Display.allCases) { item in
                            Label(item.title, systemImage: item.symbol).tag(item)
                        }
                    }
                } label: {
                    Image(systemName: display.symbol)
                        .font(.system(size: 18, weight: .medium))
                        .frame(width: Tokens.hitTarget, height: Tokens.hitTarget)
                }
                .accessibilityLabel("Режим: \(display.title). Выбрать другой")

                Menu {
                    Toggle("Показывать выполненные", isOn: $showDone)
                    Picker("Цвет задач", selection: $colorMode) {
                        ForEach(ColorMode.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                    Button("Проекты…", systemImage: "folder", action: onProjects)
                    Button("Настройки…", systemImage: "gearshape", action: onSettings)
                    Divider()
                    Text("Сборка \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?")")
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 19, weight: .medium))
                        .frame(width: Tokens.hitTarget, height: Tokens.hitTarget)
                }
                .accessibilityLabel("Ещё: выполненные, цвета, проекты, настройки")

                Button(action: onToday) {
                    Image(systemName: (1...50).contains(todayNumber) ? "\(todayNumber).square" : "calendar")
                        .font(.system(size: 21, weight: .medium))
                        .frame(width: Tokens.hitTarget, height: Tokens.hitTarget)
                }
                .accessibilityLabel("К сегодняшнему дню")
            }
            .padding(2)
            .glassEffect(.regular.tint(Tokens.cluster.opacity(0.6)), in: Capsule())
            .foregroundStyle(Tokens.text)
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .frame(height: 62)
    }
}
