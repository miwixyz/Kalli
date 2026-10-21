import EventKit
import Foundation
import OSLog

/// Schreiben in Apple Erinnerungen für die Eingabezeile „Neue Erinnerung" (0.10.0).
/// Eigene Datei, damit `QuickReminder` rein bleibt (ohne EventKit testbar).
extension QuickReminder {

    struct Failure: Error, Equatable {
        let message: String
    }

    nonisolated private static let log = Logger(subsystem: "com.kalli.app", category: "erinnerungen")

    /// Legt die Erinnerung in der Standardliste an. Mit Uhrzeit bekommt sie einen Alarm zur
    /// Fälligkeit — wie in Apples App; ein reines Fälligkeitsdatum klingelt über EventKit nicht.
    /// „Dringend" = Priorität 1. Liefert die Kennung der neuen Erinnerung.
    @MainActor
    static func save(_ draft: Draft, in store: EKEventStore, calendar: Calendar) -> Result<String, Failure> {
        guard EKEventStore.authorizationStatus(for: .reminder) == .fullAccess else {
            return .failure(.init(message: "Kein Zugriff auf Erinnerungen."))
        }
        guard let list = store.defaultCalendarForNewReminders() else {
            return .failure(.init(message: "Keine Standardliste in Apple Erinnerungen gefunden."))
        }
        guard let fields = fields(for: draft, calendar: calendar) else {
            return .failure(.init(message: "Bitte einen Titel eingeben."))
        }
        let reminder = EKReminder(eventStore: store)
        reminder.calendar = list
        reminder.title = fields.title
        reminder.dueDateComponents = fields.due
        reminder.priority = fields.priority
        if let alarm = fields.alarmDate { reminder.addAlarm(EKAlarm(absoluteDate: alarm)) }
        do {
            try store.save(reminder, commit: true)
        } catch {
            log.error("Anlegen fehlgeschlagen — Liste \(list.title, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return .failure(.init(message: error.localizedDescription))
        }
        log.notice("Erinnerung gespeichert — Liste \(list.title, privacy: .public), Uhrzeit \(fields.alarmDate != nil, privacy: .public), dringend \(draft.urgent, privacy: .public)")
        return .success(reminder.calendarItemIdentifier)
    }

    /// NACHLESEN STATT GLAUBEN (siehe `CalendarStore.setCompleted`): Ein `save()` ohne Fehler
    /// heißt nur, dass der Aufruf durchlief. `nil` = angekommen, sonst die Meldung.
    @MainActor
    static func verify(id: String, title: String, in store: EKEventStore) -> String? {
        let expected = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let fresh = store.calendarItem(withIdentifier: id) as? EKReminder, fresh.title == expected else {
            log.error("Neue Erinnerung NICHT angekommen")
            return "Die Erinnerung ist nicht angekommen — Apple Erinnerungen hat sie nicht übernommen."
        }
        log.notice("Neue Erinnerung bestätigt")
        return nil
    }
}
