import Foundation

/// Schnell eine Erinnerung anlegen (0.10.0, Michael 2026-10-21): Titel, Tag, Uhrzeit, „Dringend".
///
/// Tag und Uhrzeit kommen aus Knöpfen **oder** aus dem Titel („Zahnarzt morgen 15 Uhr").
/// Die Erkennung ist bewusst klein: deutsche Wörter für die nächsten Tage, Wochentage,
/// „nächste Woche", ein Datum `24.10.` und eine Uhrzeit. Kein allgemeiner Sprach-Parser —
/// was nicht erkannt wird, bleibt einfach im Titel stehen und man nimmt die Knöpfe.
enum QuickReminder {

    /// Was die Eingabezeile hält. `day` ist der Tagesbeginn, `time` Stunde und Minute.
    struct Draft: Equatable {
        var title: String
        var day: Date
        var time: Time?
        var urgent: Bool
    }

    struct Time: Equatable, Hashable {
        let hour: Int
        let minute: Int

        var label: String { String(format: "%d:%02d", hour, minute) }
    }

    /// Was in EventKit landet.
    struct Fields: Equatable {
        let title: String
        let due: DateComponents
        let priority: Int
        /// Mit Uhrzeit: Alarm zur Fälligkeit, damit Apple Erinnerungen meldet.
        let alarmDate: Date?
    }

    /// Ergebnis der Texterkennung: Titel ohne die erkannten Angaben.
    struct Parsed: Equatable {
        var title: String
        var day: Date?
        var time: Time?
    }

    /// EventKit-Priorität für „Dringend": 1 = höchste (Apple Erinnerungen zeigt „!!!").
    nonisolated static let urgentPriority = 1

    /// RFC 5545: 1–4 hoch, 5 mittel, 6–9 niedrig, 0 keine.
    nonisolated static func isHighPriority(_ priority: Int) -> Bool {
        (1...4).contains(priority)
    }

    /// Feste Uhrzeiten der Knöpfe.
    nonisolated static let presetTimes = [Time(hour: 9, minute: 0), Time(hour: 12, minute: 0),
                                          Time(hour: 18, minute: 0)]

    // MARK: - Draft → EventKit

    /// `nil` bei leerem Titel.
    nonisolated static func fields(for draft: Draft, calendar: Calendar) -> Fields? {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        var due = calendar.dateComponents([.year, .month, .day], from: draft.day)
        var alarm: Date?
        if let time = draft.time {
            due.hour = time.hour
            due.minute = time.minute
            alarm = calendar.date(bySettingHour: time.hour, minute: time.minute, second: 0, of: draft.day)
        }
        // Die Zeitzone gehört dazu, sonst deutet EventKit die Komponenten als „schwebend".
        due.timeZone = calendar.timeZone
        return Fields(title: title, due: due, priority: draft.urgent ? urgentPriority : 0, alarmDate: alarm)
    }

    // MARK: - Knöpfe

    enum DayChoice: CaseIterable {
        case today, tomorrow, nextWeek

        var title: String {
            switch self {
            case .today: "Heute"
            case .tomorrow: "Morgen"
            case .nextWeek: "Nächste Woche"
            }
        }
    }

    /// „Nächste Woche" = Montag der kommenden Woche (wie Apple Erinnerungen).
    nonisolated static func day(_ choice: DayChoice, now: Date, calendar: Calendar) -> Date {
        let today = calendar.startOfDay(for: now)
        switch choice {
        case .today: return today
        case .tomorrow: return calendar.date(byAdding: .day, value: 1, to: today) ?? today
        case .nextWeek: return nextWeekday(2, after: today, calendar: calendar, skipThisWeek: true)
        }
    }

    // MARK: - Texterkennung

    nonisolated private static let weekdays: [(name: String, weekday: Int)] = [
        ("sonntag", 1), ("montag", 2), ("dienstag", 3), ("mittwoch", 4),
        ("donnerstag", 5), ("freitag", 6), ("samstag", 7),
    ]

    /// Erkennt Tag und Uhrzeit im Text und nimmt sie aus dem Titel. Was nicht passt, bleibt stehen.
    nonisolated static func parse(_ text: String, now: Date, calendar: Calendar) -> Parsed {
        var rest = text
        let day = parseDay(&rest, now: now, calendar: calendar)
        let time = parseTime(&rest)
        let title = rest.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,;-–"))
        return Parsed(title: title, day: day, time: time)
    }

    /// Reihenfolge zählt: Datum zuerst („24.10." ist keine 24:10), „übermorgen" vor „morgen".
    nonisolated private static func parseDay(_ rest: inout String, now: Date, calendar: Calendar) -> Date? {
        let today = calendar.startOfDay(for: now)
        if let m = take(#"(?:am\s+)?(\d{1,2})\.(\d{1,2})\.(\d{2,4})?"#, from: &rest),
           let d = m[1].flatMap({ Int($0) }), let mo = m[2].flatMap({ Int($0) }) {
            return date(day: d, month: mo, year: m[3].flatMap { Int($0) }, today: today, calendar: calendar)
        }
        let relative: [(pattern: String, days: Int)] = [("übermorgen", 2), ("morgen", 1), ("heute", 0)]
        for entry in relative where take(entry.pattern, from: &rest) != nil {
            return calendar.date(byAdding: .day, value: entry.days, to: today)
        }
        if take(#"nächste[nr]?\s+woche"#, from: &rest) != nil {
            return day(.nextWeek, now: now, calendar: calendar)
        }
        for (name, weekday) in weekdays
        where take(#"(?:(?:am|nächsten|nächster|kommenden)\s+)?"# + name, from: &rest) != nil {
            return nextWeekday(weekday, after: today, calendar: calendar, skipThisWeek: false)
        }
        return nil
    }

    /// „15:30", „15:30 Uhr", „15.30 Uhr", „15 Uhr", „um 9". Ungültige Zeiten bleiben im Titel.
    nonisolated private static func parseTime(_ rest: inout String) -> Time? {
        let patterns = [
            #"(?:um\s+)?(\d{1,2}):(\d{2})(?:\s*uhr)?"#,
            #"(?:um\s+)?(\d{1,2})\.(\d{2})\s*uhr"#,
            #"(?:um\s+)?(\d{1,2})\s*uhr"#,
            #"um\s+(\d{1,2})(?:\.(\d{2}))?"#,
        ]
        for pattern in patterns {
            var probe = rest
            guard let m = take(pattern, from: &probe), let h = m[1].flatMap({ Int($0) }) else { continue }
            let minute = m.count > 2 ? m[2].flatMap { Int($0) } ?? 0 : 0
            guard (0...23).contains(h), (0...59).contains(minute) else { continue }
            rest = probe
            return Time(hour: h, minute: minute)
        }
        return nil
    }

    /// Entfernt den ersten Treffer (ganzes Wort, Groß/klein egal) und gibt die Gruppen zurück.
    nonisolated private static func take(_ pattern: String, from text: inout String) -> [String?]? {
        let bounded = #"(?<![\p{L}\d])"# + pattern + #"(?![\p{L}\d])"#
        guard let regex = try? NSRegularExpression(pattern: bounded, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let whole = Range(match.range, in: text) else { return nil }
        let groups: [String?] = (0..<match.numberOfRanges).map { i in
            Range(match.range(at: i), in: text).map { String(text[$0]) }
        }
        text.replaceSubrange(whole, with: " ")
        return groups
    }

    /// Ohne Jahr: dieses Jahr, liegt der Tag schon zurück, das nächste. Zweistellig → 20xx.
    nonisolated private static func date(day: Int, month: Int, year: Int?, today: Date, calendar: Calendar) -> Date? {
        let thisYear = calendar.component(.year, from: today)
        let fullYear = year.map { $0 < 100 ? 2000 + $0 : $0 }
        func make(_ y: Int) -> Date? {
            let c = DateComponents(year: y, month: month, day: day)
            guard c.isValidDate(in: calendar), let d = calendar.date(from: c) else { return nil }
            return d
        }
        if let fullYear { return make(fullYear) }
        guard let candidate = make(thisYear) else { return nil }
        return candidate < today ? make(thisYear + 1) : candidate
    }

    /// Nächster Tag mit diesem Wochentag nach `today` (1…7 Tage). `skipThisWeek`: erst ab
    /// der kommenden Kalenderwoche (für „nächste Woche").
    nonisolated private static func nextWeekday(_ weekday: Int, after today: Date,
                                                calendar: Calendar, skipThisWeek: Bool) -> Date {
        if skipThisWeek,
           let week = calendar.dateInterval(of: .weekOfYear, for: today),
           let nextWeekStart = calendar.date(byAdding: .day, value: 7, to: week.start) {
            // Montag der nächsten Woche, unabhängig vom eingestellten Wochenbeginn.
            let days = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: nextWeekStart) }
            if let d = days.first(where: { calendar.component(.weekday, from: $0) == weekday }) { return d }
        }
        let days = (1...7).compactMap { calendar.date(byAdding: .day, value: $0, to: today) }
        if let d = days.first(where: { calendar.component(.weekday, from: $0) == weekday }) { return d }
        return today
    }
}
