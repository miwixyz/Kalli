import Foundation
@testable import Kalli

/// Bausteine für die Tests.
///
/// **Alle Zeiten leiten sich von einem festen `now` ab**, nie von `Date()`.
/// Ein Test, der die Systemuhr befragt, schlägt irgendwann nachts oder an einem
/// Monatsende fehl — und wird dann ignoriert statt gelesen. Genau diese
/// Abhängigkeit war der Grund, die Auswahllogik überhaupt in reine Funktionen
/// zu ziehen: `isDateInToday` fragt das System, `isDate(_:inSameDayAs:)` fragt
/// das übergebene `now`.
enum Fixture {

    /// Fester Kalender mit fester Zeitzone. Ohne beides wären die
    /// Tagesgrenzen-Tests davon abhängig, wo der Rechner steht.
    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Berlin")!
        c.locale = Locale(identifier: "de_DE")
        return c
    }

    /// Dienstag, 22. September 2026, 12:00 Ortszeit.
    ///
    /// Mittags gewählt, damit ±11 Stunden noch im selben Tag liegen und
    /// größere Abstände zuverlässig in den Nachbartag fallen.
    static let now: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 9; c.day = 22; c.hour = 12; c.minute = 0
        return Fixture.calendar.date(from: c)!
    }()

    static func at(_ minutes: Double) -> Date {
        now.addingTimeInterval(minutes * 60)
    }

    /// Derselbe Tag, aber **06:00** — gebraucht für die Tagesgrenzen-Regel.
    ///
    /// Mit `now` = 12:00 ist diese Regel von der 12-Stunden-Regel verdeckt: Ein
    /// Termin, der mittags läuft und höchstens 12 Stunden dauert, muss um
    /// Mitternacht oder später begonnen haben — also heute. Die Tagesgrenze
    /// greift nur am frühen Morgen. Am 2026-09-22 bestand der zugehörige Test
    /// deshalb auch mit entfernter Prüfung: aus dem falschen Grund, gefunden
    /// durch eine Mutationsprobe.
    static let earlyMorning: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 9; c.day = 22; c.hour = 6; c.minute = 0
        return Fixture.calendar.date(from: c)!
    }()

    static func atEarly(_ minutes: Double) -> Date {
        earlyMorning.addingTimeInterval(minutes * 60)
    }

    /// Termin. `hasAlarms` ist bewusst ein benannter Parameter ohne Vorgabe in
    /// den Tests, die ihn prüfen — die Regel „kein Doppel-Alarm" soll man im
    /// Testaufruf lesen können.
    static func event(
        id: String = UUID().uuidString,
        title: String = "Termin",
        start: Date?,
        end: Date?,
        isAllDay: Bool = false,
        hasAlarms: Bool = false
    ) -> AgendaItem {
        AgendaItem(
            id: id, title: title, start: start, end: end,
            isAllDay: isAllDay, hasTime: !isAllDay, kind: .event,
            sourceID: "cal", color: .fallback, hasAlarms: hasAlarms
        )
    }

    static func reminder(
        id: String = UUID().uuidString,
        title: String = "Aufgabe",
        due: Date?,
        hasTime: Bool = true,
        completed: Bool = false
    ) -> AgendaItem {
        AgendaItem(
            id: id, title: title, start: due, end: nil,
            isAllDay: false, hasTime: hasTime, kind: .reminder(completed: completed),
            sourceID: "list", color: .fallback, hasAlarms: false
        )
    }
}
