import PlannerCore
import SwiftUI

/// Главная задача словами и временем — общая для маленького виджета, карточки большого
/// и экрана блокировки: подпись («СЕЙЧАС», «ЧЕРЕЗ»…), время (живой отсчёт или текст) и строка под ним.
struct FocusHero {
    var label: String
    var labelColor: Color
    /// Живой отсчёт до этого момента; без него — `text`.
    var countdownTo: Date?
    var text = ""
    var valueColor: Color
    /// Под временем: «11:30–12:30», «в 15:00 · 45 мин».
    var meta: String
    /// Подпись под временем в карточке большого: «осталось», «до начала».
    var caption = ""
    /// Кончилась и не отмечена — спросить «Готово?».
    var ask = false
}

extension FocusHero {
    init(state: DayState, item: WidgetSnapshot.Item) {
        let range = WidgetText.range(item)
        let start = item.start ?? 0
        switch state.timing(item) {
        case .now:
            self = FocusHero(label: "СЕЙЧАС", labelColor: WidgetPalette.accent,
                             countdownTo: state.moment(start + item.duration), valueColor: WidgetPalette.accent,
                             meta: range, caption: "осталось")
        case .missed(let ago):
            let label = ago <= WidgetSnapshot.justEndedWindow ? "ТОЛЬКО ЧТО" : "БЫЛО В " + ClockGrid.format(minutes: start)
            self = FocusHero(label: label, labelColor: WidgetPalette.caption, text: "Готово?",
                             valueColor: WidgetPalette.ask, meta: range, ask: true)
        case .later(let minutes) where minutes <= WidgetSnapshot.freeTimeThreshold:
            self = FocusHero(label: "ЧЕРЕЗ", labelColor: WidgetPalette.text, countdownTo: state.moment(start),
                             valueColor: WidgetPalette.text, meta: range, caption: "до начала")
        case .later(let minutes):
            self = FocusHero(label: "ДАЛЬШЕ", labelColor: WidgetPalette.caption, text: ClockGrid.format(minutes: start),
                             valueColor: WidgetPalette.text, meta: "через " + WidgetText.roughHours(minutes),
                             caption: "начало")
        case .allDay:
            if state.atRisk {
                self = FocusHero(label: "ОГОНЁК ГАСНЕТ", labelColor: WidgetPalette.flame, countdownTo: state.midnight,
                                 valueColor: WidgetPalette.flame, meta: "сделай одну", caption: "до полуночи")
            } else if let next = state.snapshot.nextTimed(after: state.minutes), let nextStart = next.start {
                // До следующей задачи с временем свободно: вот чем его занять.
                let time = ClockGrid.format(minutes: nextStart)
                let soon = nextStart - state.minutes <= 180
                self = FocusHero(label: "СВОБОДНО", labelColor: WidgetPalette.accent,
                                 countdownTo: soon ? state.moment(nextStart) : nil, text: "до " + time,
                                 valueColor: WidgetPalette.accent, meta: soon ? "до " + time : "потом в " + time,
                                 caption: "свободно")
            } else {
                let others = state.agenda.filter { $0.start == nil && $0.id != item.id }.count
                self = FocusHero(label: "БЕЗ ВРЕМЕНИ", labelColor: WidgetPalette.caption, text: "Весь день",
                                 valueColor: WidgetPalette.text,
                                 meta: others > 0 ? "+\(others) без времени" : "на сегодня")
            }
        case .overdue(let day):
            self = FocusHero(label: "ПРОСРОЧЕНО", labelColor: WidgetPalette.overdue,
                             text: WidgetText.capitalized(WidgetText.overdueDay(day, today: state.snapshot.day)),
                             valueColor: WidgetPalette.overdue,
                             meta: item.start.map { "было в " + ClockGrid.format(minutes: $0) } ?? "весь день")
        case .done:
            self = FocusHero(label: "СДЕЛАНО", labelColor: WidgetPalette.muted, text: "Готово",
                             valueColor: WidgetPalette.muted, meta: range)
        }
    }

    /// Время крупно: живой отсчёт (под час — крупнее) или текст, ужимающийся в колонку.
    @ViewBuilder
    func value(from date: Date, width: CGFloat, large: CGFloat, small: CGFloat, leading: Bool = true) -> some View {
        if let countdownTo {
            let size = countdownTo.timeIntervalSince(date) < 3600 ? large : small
            // «5:59:59» на 24 pt шире колонки маленького экрана (SE, mini) — ужимается до 18 pt.
            Countdown(from: date, to: countdownTo, font: .system(size: size, weight: .bold, design: .rounded),
                      color: valueColor, width: width, leading: leading, minScale: 0.75)
                .widgetAccentable()
        } else {
            Text(text)
                .font(.system(size: large - 2, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .frame(maxWidth: width, alignment: leading ? .leading : .trailing)
                .widgetAccentable()
        }
    }
}
