import SwiftUI

/// Monatsraster. Immer sechs Zeilen, damit das Popover beim Monatswechsel nicht
/// in der Höhe springt.
struct MonthGrid: View {

    let month: Date
    @Binding var selection: Date
    let calendar: Calendar
    let showWeekNumbers: Bool
    let hasItems: (Date) -> Bool

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
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(width: 22)
                }
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 30)
                }
            }

            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                GridRow {
                    if showWeekNumbers, let first = week.first {
                        Text("\(calendar.component(.weekOfYear, from: first))")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                            .frame(width: 22)
                    }
                    ForEach(week, id: \.self) { day in
                        DayCell(
                            day: day,
                            isToday: calendar.isDateInToday(day),
                            isSelected: calendar.isDate(day, inSameDayAs: selection),
                            isInMonth: calendar.isDate(day, equalTo: month, toGranularity: .month),
                            hasItems: hasItems(day),
                            dayNumber: calendar.component(.day, from: day)
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

    var body: some View {
        VStack(spacing: 1) {
            Text("\(dayNumber)")
                .font(.system(size: 12, weight: isToday ? .bold : .regular))
                .monospacedDigit()
            Circle()
                .frame(width: 3, height: 3)
                .opacity(hasItems ? 1 : 0)
        }
        .foregroundStyle(foreground)
        .frame(width: 30, height: 30)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 7).fill(.tint.opacity(0.25))
            } else if isToday {
                RoundedRectangle(cornerRadius: 7).fill(.tint.opacity(0.14))
            }
        }
        .overlay {
            if isToday {
                RoundedRectangle(cornerRadius: 7).strokeBorder(.tint, lineWidth: 1)
            }
        }
        .contentShape(Rectangle())
    }

    /// Tage aus Nachbarmonaten bleiben sichtbar, treten aber zurück.
    private var foreground: HierarchicalShapeStyle {
        isInMonth ? .primary : .quaternary
    }
}
