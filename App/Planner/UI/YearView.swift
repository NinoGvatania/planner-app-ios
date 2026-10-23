import SwiftUI

/// Год: двенадцать маленьких месяцев, дни с задачами отмечены точкой, сегодня — кружком.
/// Тап по месяцу открывает его. Месяцы делят всю высоту до острова (4 ряда по 3): строки дней и числа
/// крупнее, а не островок сверху с пустотой снизу. Если места мало — прокрутка, как раньше.
struct YearView: View {
    let year: Int
    let tasks: [PlannerTask]
    /// Сколько снизу закрывает свёрнутый остров.
    var bottomInset: CGFloat = 0
    let onSelectMonth: (Date) -> Void

    private var markedDays: Set<Date> { Set(tasks.compactMap(\.day)) }

    private let columns = 3
    private let spacing: CGFloat = 8
    private let outerPadding: CGFloat = 8
    /// Название месяца с отступом под ним и поля карточки сверху и снизу.
    private let titleBlock: CGFloat = 22
    private let cardPadding: CGFloat = 8
    private let minRow: CGFloat = 17
    private let maxRow: CGFloat = 32

    var body: some View {
        let marked = markedDays
        let today = DayMath.today()
        GeometryReader { geometry in
            let cellWidth = max(80, (geometry.size.width - outerPadding * 2 - spacing * CGFloat(columns - 1)) / CGFloat(columns))
            // Высота строки дня — чтобы четыре ряда месяцев заняли всё место над островом.
            let available = geometry.size.height - bottomInset - 6 - spacing * 3
            let cardHeight = available / 4
            let row = min(maxRow, max(minRow, (cardHeight - titleBlock - cardPadding * 2) / 6))
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(cellWidth), spacing: spacing), count: columns), spacing: spacing) {
                    ForEach(0..<12, id: \.self) { month in
                        let start = DayMath.monthStart(year: year, month: month)
                        miniMonth(start: start, month: month, marked: marked, today: today, width: cellWidth, row: row)
                    }
                }
                .padding(.horizontal, outerPadding)
                .padding(.top, 6)
            }
            .contentMargins(.bottom, bottomInset, for: .scrollContent)
            // Влезает целиком — не пружинит; не влезает (маленький экран, крупный шрифт) — прокручивается.
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private func miniMonth(start: Date, month: Int, marked: Set<Date>, today: Date, width: CGFloat, row: CGFloat) -> some View {
        let first = DayMath.offset(of: start)
        let gridStart = DayMath.weekStartOffset(containing: first)
        let isCurrent = DayMath.monthIndex(today) == month && DayMath.year(today) == year
        let cell = (width - 4) / 7
        // Число растёт со строкой, но двузначное должно влезать в ширину клетки.
        let font = min(15, max(11, min(row * 0.62, cell * 0.7)))
        let todaySize = min(row - 1, cell - 1, font + 8)
        return VStack(alignment: .leading, spacing: 4) {
            Text(DayMath.monthNominative[month])
                .font(.system(size: row > 22 ? 14 : 13, weight: .bold))
                .foregroundStyle(isCurrent ? Tokens.accent : Tokens.text)
                .lineLimit(1)
                .frame(height: titleBlock - 4, alignment: .leading)
                .padding(.leading, 4)
            VStack(spacing: 0) {
                ForEach(0..<6, id: \.self) { line in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { column in
                            let offset = gridStart + line * 7 + column
                            let date = DayMath.day(offset: offset)
                            let inMonth = DayMath.monthIndex(date) == month && DayMath.year(date) == year
                            ZStack {
                                if inMonth {
                                    if date == today {
                                        Circle().fill(Tokens.accent).frame(width: todaySize, height: todaySize)
                                    }
                                    Text("\(DayMath.dayOfMonth(date))")
                                        .font(.system(size: font, weight: date == today ? .bold : .regular))
                                        .monospacedDigit()
                                        .foregroundStyle(date == today ? Tokens.onAccent : (column >= 5 ? Tokens.weekend.opacity(0.85) : Tokens.caption))
                                    if marked.contains(date), date != today {
                                        Circle().fill(Tokens.accent).frame(width: 3, height: 3).offset(y: min(row / 2 - 2, font / 2 + 4))
                                    }
                                }
                            }
                            .frame(width: cell, height: row)
                        }
                    }
                }
            }
        }
        .padding(.vertical, cardPadding)
        .padding(.horizontal, 2)
        .frame(width: width, alignment: .leading)
        .background(Tokens.panel, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(isCurrent ? Tokens.accent.opacity(0.5) : Color.white.opacity(0.06), lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onPageTap { onSelectMonth(start) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DayMath.monthNominative[month] + " \(year)")
        .accessibilityAddTraits(.isButton)
    }
}
