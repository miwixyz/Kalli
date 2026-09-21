import SwiftUI

/// Monatsraster. Immer sechs Zeilen, damit das Popover beim Monatswechsel nicht
/// in der Höhe springt.
struct MonthGrid: View {

    let month: Date
    @Binding var selection: Date
    let calendar: Calendar
    let showWeekNumbers: Bool
    var scale: Double = 1.0
    let hasItems: (Date) -> Bool

    private var cellW: CGFloat { 44 * scale }
    private var cellH: CGFloat { 40 * scale }
    private var weekW: CGFloat { 30 * scale }

    private var weeks: [[Date]] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: interval.start)
        else { return [] }

        var days: [Date] = []
        var cursor = firstWeek.start
        for _ in 0..<42 {                      // 6 Wochen × 7 Tage, fest
            days.append(cursor)
            cursor = calendar.date(byAdding: .day, value: 1, to: cursor) ?? cursor
        }
        return stride(from: 0, to: 42, by: 7).map { Array(days[$0..<$0 + 7]) }
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.shortWeekdaySymbols
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    var body: some View {
        Grid(horizontalSpacing: 2, verticalSpacing: 2) {
            GridRow {
                if showWeekNumbers {
                    Text("KW")
                        .font(Theme.font(Theme.Size.weekNumber, scale))
                        .foregroundStyle(.tertiary)
                        .frame(width: weekW)
                }
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(Theme.font(Theme.Size.weekday, scale, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: cellW)
                }
            }

            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                GridRow {
                    if showWeekNumbers, let first = week.first {
                        Text("\(calendar.component(.weekOfYear, from: first))")
                            .font(Theme.font(Theme.Size.weekNumber, scale))
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                            .frame(width: weekW)
                    }
                    ForEach(week, id: \.self) { day in
                        DayCell(
                            day: day,
                            isToday: calendar.isDateInToday(day),
                            isSelected: calendar.isDate(day, inSameDayAs: selection),
                            isInMonth: calendar.isDate(day, equalTo: month, toGranularity: .month),
                            hasItems: hasItems(day),
                            dayNumber: calendar.component(.day, from: day),
                            width: cellW, height: cellH, scale: scale
                        )
                        .onTapGesture { selection = day }
                    }
                }
            }
        }
    }
}

private struct DayCell: View {
    let day: Date
    let isToday: Bool
    let isSelected: Bool
    let isInMonth: Bool
    let hasItems: Bool
    let dayNumber: Int
    let width: CGFloat
    let height: CGFloat
    let scale: Double

    var body: some View {
        VStack(spacing: 1) {
            Text("\(dayNumber)")
                                .font(Theme.font(Theme.Size.dayNumber, scale,
                                 weight: isToday ? .semibold : .regular))
                .monospacedDigit()
            // Kräftiger als zuvor: bei 3 pt und .quaternary war kaum zu sehen,
            // an welchen Tagen etwas steht.
            Circle()
                .frame(width: 4.5 * scale, height: 4.5 * scale)
                .opacity(hasItems ? 0.8 : 0)
        }
        .foregroundStyle(todayStyle)
        .frame(width: width, height: height)
        .background {
            // Heute = gefuellter Kreis mit Verlauf. Ein Kreis wirkt leichter
            // als eine Kachel und ist die Form, die Apple in Kalender und
            // Erinnerungen fuer "jetzt" verwendet.
            //
            // Markiert = Ring. Zwei Zustaende brauchen zwei Gestalten, nicht
            // dieselbe Farbe in zwei Helligkeiten.
            if isToday {
                Circle()
                    .fill(Theme.accentFill)
                    .frame(width: min(width, height) - 4 * scale,
                           height: min(width, height) - 4 * scale)
                    .shadow(color: Theme.accentGlow, radius: 5 * scale, y: 1.5 * scale)
            } else if isSelected {
                Circle()
                    .fill(.primary.opacity(0.07))
                    .frame(width: min(width, height) - 4 * scale,
                           height: min(width, height) - 4 * scale)
            }
        }
        .overlay {
            if isSelected {
                Circle()
                    .strokeBorder(
                        isToday ? AnyShapeStyle(.white.opacity(0.85))
                                : AnyShapeStyle(Theme.accent.opacity(0.75)),
                        lineWidth: 1.6
                    )
                    .frame(width: min(width, height) - 4 * scale,
                           height: min(width, height) - 4 * scale)
            }
        }
        .contentShape(Rectangle())
    }

    /// Auf gefülltem Akzenthintergrund muss der Text weiß sein, sonst steht
    /// Blau auf Blau.
    private var todayStyle: AnyShapeStyle {
        if isToday { return AnyShapeStyle(.white) }
        return AnyShapeStyle(isInMonth ? AnyShapeStyle(.primary) : AnyShapeStyle(.quaternary))
    }

}
