import SwiftUI

/// Год: двенадцать маленьких месяцев, дни с задачами отмечены точкой, сегодня — кружком.
/// Тап по месяцу открывает его.
struct YearView: View {
    let year: Int
    let tasks: [PlannerTask]
    let onSelectMonth: (Date) -> Void

    private var markedDays: Set<Date> { Set(tasks.compactMap(\.day)) }

    var body: some View {
        let marked = markedDays
        let today = DayMath.today()
        GeometryReader { geometry in
            let columns = 3
            let spacing: CGFloat = 10
            let cellWidth = max(80, (geometry.size.width - 20 - spacing * CGFloat(columns - 1)) / CGFloat(columns))
            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(cellWidth), spacing: spacing), count: columns), spacing: 12) {
                    ForEach(0..<12, id: \.self) { month in
                        let start = DayMath.monthStart(year: year, month: month)
                        miniMonth(start: start, month: month, marked: marked, today: today, width: cellWidth)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 6)
                .padding(.bottom, 16)
            }
        }
    }

    private func miniMonth(start: Date, month: Int, marked: Set<Date>, today: Date, width: CGFloat) -> some View {
        let first = DayMath.offset(of: start)
        let gridStart = DayMath.weekStartOffset(containing: first)
        let isCurrent = DayMath.monthIndex(today) == month && DayMath.year(today) == year
        let cell = (width - 6) / 7
        return VStack(alignment: .leading, spacing: 4) {
            Text(DayMath.monthNominative[month])
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(isCurrent ? Tokens.accent : Tokens.text)
                .lineLimit(1)
                .padding(.leading, 3)
            VStack(spacing: 1) {
                ForEach(0..<6, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { column in
                            let offset = gridStart + row * 7 + column
                            let date = DayMath.day(offset: offset)
                            let inMonth = DayMath.monthIndex(date) == month && DayMath.year(date) == year
                            ZStack {
                                if inMonth {
                                    if date == today {
                                        Circle().fill(Tokens.accent).frame(width: 17, height: 17)
                                    }
                                    Text("\(DayMath.dayOfMonth(date))")
                                        .font(.system(size: 11, weight: date == today ? .bold : .regular))
                                        .monospacedDigit()
                                        .foregroundStyle(date == today ? Tokens.onAccent : (column >= 5 ? Tokens.weekend.opacity(0.85) : Tokens.caption))
                                    if marked.contains(date), date != today {
                                        Circle().fill(Tokens.accent).frame(width: 3, height: 3).offset(y: 8)
                                    }
                                }
                            }
                            .frame(width: cell, height: 17)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 3)
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
