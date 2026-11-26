import SwiftUI

// Bausteine des Tagesblatts im Punkti-Look, geteilt von Widget und Fenster (Aussehen „Punkti“).
// Größen richten sich nach dem verfügbaren Platz, nicht nach Kallis Textgröße.

/// Glasscheibe mit Tagesring (ein Punkt je Tag des Monats), Wochentag, LED-Tageszahl und Fußzeile —
/// wie Punktis Datum-Widget.
struct PunktiDayDisc: View {
    let date: Date
    let footer: String
    var color: Color = .white

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let calendar = Calendar.current
            let day = calendar.component(.day, from: date)
            let days = calendar.range(of: .day, in: .month, for: date)?.count ?? 30
            let weekday = date.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "de_DE"))).uppercased()
            ZStack {
                PunktiGlassDisc().frame(width: s * 0.76, height: s * 0.76)
                PunktiDotRing(position: Double(day - 1), color: color, count: days)
                VStack(spacing: s * 0.03) {
                    Text(verbatim: weekday)
                        .font(.system(size: s * 0.072, weight: .semibold, design: .monospaced))
                        .tracking(s * 0.006)
                        .foregroundStyle(color.opacity(0.92))
                    HStack(spacing: s * 0.025) {
                        PunktiSegmentDigit(digit: day >= 10 ? day / 10 : nil, color: color)
                            .frame(width: s * 0.13, height: s * 0.24)
                        PunktiSegmentDigit(digit: day % 10, color: color)
                            .frame(width: s * 0.13, height: s * 0.24)
                    }
                    Text(verbatim: footer)
                        .font(.system(size: s * 0.064, weight: .semibold, design: .monospaced))
                        .tracking(s * 0.004)
                        .foregroundStyle(color.opacity(0.85))
                }
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .frame(width: s * 0.66)
            }
            .frame(width: s, height: s)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "de_DE")))))
    }

    /// „NOV · 3 EINTRÄGE“ bzw. „NOV · FREI“.
    static func footer(for date: Date, openCount: Int?) -> String {
        let month = date.formatted(.dateTime.month(.abbreviated).locale(Locale(identifier: "de_DE")))
            .replacingOccurrences(of: ".", with: "").uppercased()
        guard let openCount else { return month }
        return openCount == 0 ? "\(month) · FREI" : "\(month) · \(openCount) \(openCount == 1 ? "EINTRAG" : "EINTRÄGE")"
    }
}

/// Eine Zeile wie in Punktis Termine-Widget: LED-Uhrzeit, darüber ein Hinweis, daneben der Titel.
/// Aufgaben ohne Uhrzeit und Ganztägiges zeigen leere LED-Stellen. Vorbei Gewesenes und Erledigtes
/// ist gedimmt. Mit `onToggle` ist der Kreis einer Aufgabe ein Knopf (Fenster), sonst nur Zeichen (Widget).
struct PunktiDayRow: View {
    let item: AgendaItem
    let now: Date
    var color: Color = .white
    /// „+2“ am Ende, wenn mehr ansteht, als Platz ist (Widget).
    var extra: String?
    var onToggle: ((AgendaItem) -> Void)?
    /// Feste Grundgröße (Fenster). Ohne: Größe aus dem Platz (Widget).
    var unit: CGFloat?

    private static let time: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HHmm"
        return f
    }()

    private var dimmed: Bool { item.isCompleted || item.isOver(at: now) }

    private var label: String {
        if item.isReminder { return item.isCompleted ? "ERLEDIGT" : "AUFGABE" }
        if item.isAllDay { return "GANZTÄGIG" }
        guard let start = item.start else { return "" }
        if item.isOver(at: now) { return "VORBEI" }
        if start <= now { return "LÄUFT" }
        let calendar = Calendar.current
        let minutes = Int(start.timeIntervalSince(now) / 60)
        if minutes < 60 { return "IN \(max(1, minutes)) MIN" }
        if calendar.isDate(start, inSameDayAs: now) { return "HEUTE" }
        if calendar.isDateInTomorrow(start) { return "MORGEN" }
        return start.formatted(.dateTime.weekday(.abbreviated).locale(Locale(identifier: "de_DE")))
            .replacingOccurrences(of: ".", with: "").uppercased()
    }

    var body: some View {
        if let unit {
            // Fenster: feste Schriftgrößen, die Zeile wächst mit dem Titel (zwei Zeilen statt Schrumpfen).
            row(u: unit, fixed: true)
                .frame(maxWidth: .infinity, minHeight: unit)
                .background(RoundedRectangle(cornerRadius: unit * 0.3, style: .continuous).fill(color.opacity(0.08)))
                .opacity(dimmed ? 0.62 : 1)
        } else {
            GeometryReader { geo in
                let w = geo.size.width, h = geo.size.height
                row(u: min(h, w * 0.3), fixed: false)
                    .frame(width: w, height: h)
                    .background(RoundedRectangle(cornerRadius: h * 0.3, style: .continuous).fill(color.opacity(0.08)))
                    .opacity(dimmed ? 0.62 : 1)
            }
        }
    }

    /// `u` ist die Grundgröße (Zeilenhöhe). Lesbarkeit (Michael 2026-11-26: „kaum lesbar“): Titel
    /// schrumpft im Fenster nicht mehr, sondern bricht um und wird gekürzt; Hinweis heller.
    private func row(u: CGFloat, fixed: Bool) -> some View {
        let digitH = u * 0.5
        let digitW = digitH * 0.53
        let digits: [Int?] = item.hasTime && !item.isAllDay
            ? Array(item.start.map { Self.time.string(from: $0) } ?? "").map(\.wholeNumberValue)
            : [nil, nil, nil, nil]
        return HStack(spacing: u * 0.18) {
            HStack(spacing: digitW * 0.2) {
                digit(digits, 0, digitW, digitH)
                digit(digits, 1, digitW, digitH)
                VStack(spacing: digitH * 0.22) {
                    Circle().frame(width: digitH * 0.1, height: digitH * 0.1)
                    Circle().frame(width: digitH * 0.1, height: digitH * 0.1)
                }
                .foregroundStyle(color.opacity(digits.contains { $0 != nil } ? 0.9 : 0.09))
                digit(digits, 2, digitW, digitH)
                digit(digits, 3, digitW, digitH)
            }
            VStack(alignment: .leading, spacing: u * 0.04) {
                HStack(spacing: u * 0.08) {
                    if item.isReminder { checkmark(size: u * 0.22) }
                    Text(verbatim: label)
                }
                .font(.system(size: u * 0.2, weight: .semibold, design: .monospaced))
                .tracking(u * 0.015)
                .foregroundStyle(color.opacity(0.8))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                Text(verbatim: item.title.isEmpty ? "OHNE TITEL" : item.title)
                    .font(.system(size: u * (fixed ? 0.28 : 0.24), weight: .medium, design: .rounded))
                    .foregroundStyle(color)
                    .strikethrough(item.isCompleted, color: color.opacity(0.6))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .minimumScaleFactor(fixed ? 1 : 0.8)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, fixed ? u * 0.14 : 0)
            Spacer(minLength: 0)
            if let extra {
                Text(verbatim: extra)
                    .font(.system(size: u * 0.2, weight: .semibold, design: .monospaced))
                    .foregroundStyle(color.opacity(0.75))
            }
        }
        .padding(.horizontal, u * 0.2)
    }

    @ViewBuilder
    private func checkmark(size: CGFloat) -> some View {
        let symbol = Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
            .font(.system(size: size, weight: .bold))
        if let onToggle {
            Button { onToggle(item) } label: { symbol.padding(size * 0.3).contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .padding(-size * 0.3)
                .help(item.isCompleted ? "Als offen markieren" : "Abhaken")
                .accessibilityLabel(Text(item.isCompleted ? "Als offen markieren" : "Abhaken"))
        } else {
            symbol
        }
    }

    private func digit(_ digits: [Int?], _ index: Int, _ w: CGFloat, _ h: CGFloat) -> some View {
        PunktiSegmentDigit(digit: digits.indices.contains(index) ? digits[index] : nil, color: color)
            .frame(width: w, height: h)
    }
}

/// Monat wie Punktis Minikalender: Titel, Wochentagskopf, Zahlen, der gezeigte Tag eingekreist.
/// Wochenaufteilung aus `DeskPad` (dieselbe wie im Papierblatt).
struct PunktiMonthGrid: View {
    let date: Date
    var color: Color = .white

    var body: some View {
        let calendar = Calendar.current
        let weeks = DeskPad.monthWeeks(for: date, calendar: calendar)
        let current = calendar.component(.day, from: date)
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let heads = (0..<7).map { symbols[(calendar.firstWeekday - 1 + $0) % 7].prefix(2).uppercased() }
        GeometryReader { geo in
            let cellW = geo.size.width / 7
            let lineH = geo.size.height / CGFloat(weeks.count + 2)
            VStack(spacing: 0) {
                Text(verbatim: date.formatted(.dateTime.month(.wide).year().locale(Locale(identifier: "de_DE"))).uppercased())
                    .font(.system(size: lineH * 0.55, weight: .medium, design: .monospaced))
                    .tracking(lineH * 0.06)
                    .foregroundStyle(color.opacity(0.85))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .frame(height: lineH)
                HStack(spacing: 0) {
                    ForEach(Array(heads.enumerated()), id: \.offset) { _, head in
                        Text(verbatim: head)
                            .font(.system(size: lineH * 0.48, weight: .semibold, design: .monospaced))
                            .foregroundStyle(color.opacity(0.7))
                            .frame(width: cellW, height: lineH)
                    }
                }
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    HStack(spacing: 0) {
                        ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                            ZStack {
                                if let day {
                                    if day == current {
                                        Circle().strokeBorder(color.opacity(0.95), lineWidth: max(1.5, lineH * 0.07))
                                            .frame(height: lineH * 0.92)
                                    }
                                    Text(verbatim: "\(day)")
                                        .font(.system(size: lineH * 0.6, weight: day == current ? .bold : .medium,
                                                      design: .rounded))
                                        .foregroundStyle(color)
                                }
                            }
                            .frame(width: cellW, height: lineH)
                        }
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}
