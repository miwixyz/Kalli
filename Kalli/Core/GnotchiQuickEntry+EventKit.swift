import EventKit
import Foundation
import OSLog

/// Speichern und Zurücknehmen für die Schnelleingabe aus Gnotchi (G61). Eigene Datei, damit `GnotchiQuickEntry`
/// rein bleibt. Erinnerungen mit Datum laufen über `QuickReminder.fields` (dieselbe Fälligkeit, derselbe Alarm wie
/// Kallis Eingabezeile). Nach jedem Schreiben wird nachgelesen — ein `save()` ohne Fehler heißt nur, dass der
/// Aufruf durchlief (siehe `QuickReminder.verify`). Nie Titel ins Protokoll.
extension GnotchiQuickEntry {

    nonisolated private static let log = Logger(subsystem: "com.kalli.app", category: "schnelleingabe")

    /// Legt an und liefert die EventKit-Kennung, sonst die Meldung für Gnotchi.
    @MainActor
    static func save(_ c: Create, in store: EKEventStore, calendar: Calendar) -> Result<String, Failure> {
        let result: Result<String, Failure>
        switch c.kind {
        case .event: result = saveEvent(c, in: store)
        case .reminder: result = saveReminder(c, in: store, calendar: calendar)
        }
        guard case .success(let id) = result else { return result }
        guard let fresh = store.calendarItem(withIdentifier: id), fresh.title == c.title else {
            log.error("Schnelleingabe NICHT angekommen — Art \(c.kind.rawValue, privacy: .public)")
            return .failure(.init(message: "Der Eintrag ist nicht angekommen."))
        }
        log.notice("Schnelleingabe gespeichert und bestätigt — Art \(c.kind.rawValue, privacy: .public), ganztägig \(c.allDay, privacy: .public)")
        return result
    }

    /// Löscht einen Eintrag, den die Schnelleingabe gerade angelegt hat, und liest nach. `nil` = weg.
    /// Nicht gefunden ist **kein** Erfolg (code-audit 19.11.): Apple dokumentiert, dass sich die Kennung bei einem
    /// vollen Abgleich ändern kann — dann stünde der Termin noch im Kalender, Gnotchi meldete aber „zurückgenommen“.
    @MainActor
    static func remove(identifier: String, kind: Kind, in store: EKEventStore) -> String? {
        let notFound = "Eintrag nicht gefunden. Bitte in Apple Kalender bzw. Erinnerungen prüfen."
        do {
            switch kind {
            case .event:
                guard let event = store.calendarItem(withIdentifier: identifier) as? EKEvent else {
                    log.error("Rückgängig: Termin nicht gefunden")
                    return notFound
                }
                try store.remove(event, span: .thisEvent, commit: true)
            case .reminder:
                guard let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else {
                    log.error("Rückgängig: Erinnerung nicht gefunden")
                    return notFound
                }
                try store.remove(reminder, commit: true)
            }
        } catch {
            log.error("Rückgängig fehlgeschlagen — \(error.localizedDescription, privacy: .public)")
            return "Rückgängig hat nicht geklappt."
        }
        guard store.calendarItem(withIdentifier: identifier) == nil else {
            log.error("Rückgängig: Eintrag noch da")
            return "Rückgängig hat nicht geklappt."
        }
        log.notice("Schnelleingabe zurückgenommen — Art \(kind.rawValue, privacy: .public)")
        return nil
    }

    struct Failure: Error, Equatable {
        let message: String
    }

    /// Termin im Standardkalender für neue Termine. Ganztägig: nur der Tag.
    @MainActor
    private static func saveEvent(_ c: Create, in store: EKEventStore) -> Result<String, Failure> {
        guard CalendarStore.authorization(for: .event) == .fullAccess else {
            return .failure(.init(message: "Kalli hat keinen Zugriff auf den Kalender."))
        }
        guard let target = store.defaultCalendarForNewEvents else {
            return .failure(.init(message: "Kein Standardkalender in Apple Kalender gefunden."))
        }
        guard let start = c.start else { return .failure(.init(message: GnotchiQuickEntry.Rejection.invalidTime.message)) }
        let event = EKEvent(eventStore: store)
        event.calendar = target
        event.title = c.title
        event.isAllDay = c.allDay
        event.startDate = start
        event.endDate = c.allDay ? start : (c.end ?? start.addingTimeInterval(3600))
        do {
            try store.save(event, span: .thisEvent, commit: true)
        } catch {
            log.error("Termin anlegen fehlgeschlagen — \(error.localizedDescription, privacy: .public)")
            return .failure(.init(message: error.localizedDescription))
        }
        // `calendarItemIdentifier` (nicht `eventIdentifier`): dieselbe Kennung, mit der nachgelesen und
        // zurückgenommen wird (`calendarItem(withIdentifier:)`).
        return .success(event.calendarItemIdentifier)
    }

    /// Erinnerung in der Standardliste. Mit Datum über `QuickReminder.fields`, ohne Datum ohne Fälligkeit.
    @MainActor
    private static func saveReminder(_ c: Create, in store: EKEventStore, calendar: Calendar) -> Result<String, Failure> {
        guard let start = c.start else { return saveUndatedReminder(c, in: store) }
        let draft = QuickReminder.Draft(title: c.title, day: calendar.startOfDay(for: start),
                                        time: c.allDay ? nil : reminderTime(start, calendar: calendar), urgent: c.urgent)
        return QuickReminder.save(draft, in: store, calendar: calendar).mapError { Failure(message: $0.message) }
    }

    @MainActor
    private static func saveUndatedReminder(_ c: Create, in store: EKEventStore) -> Result<String, Failure> {
        guard CalendarStore.authorization(for: .reminder) == .fullAccess else {
            return .failure(.init(message: "Kein Zugriff auf Erinnerungen."))
        }
        guard let list = store.defaultCalendarForNewReminders() else {
            return .failure(.init(message: "Keine Standardliste in Apple Erinnerungen gefunden."))
        }
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = list
        reminder.title = c.title
        reminder.priority = c.urgent ? QuickReminder.urgentPriority : 0
        do {
            try store.save(reminder, commit: true)
        } catch {
            log.error("Erinnerung ohne Datum fehlgeschlagen — \(error.localizedDescription, privacy: .public)")
            return .failure(.init(message: error.localizedDescription))
        }
        return .success(reminder.calendarItemIdentifier)
    }

    /// Stunde und Minute aus dem Zeitpunkt (Gnotchi schickt Unix-Sekunden, Kalli rechnet in der eigenen Zeitzone).
    nonisolated static func reminderTime(_ date: Date, calendar: Calendar) -> QuickReminder.Time {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return QuickReminder.Time(hour: parts.hour ?? 0, minute: parts.minute ?? 0)
    }
}
