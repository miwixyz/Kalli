import EventKit
import Foundation

/// Reine Entscheidungslogik des `CalendarStore` — ohne EventKit, ohne Uhr,
/// ohne Zustand. Jede Funktion bekommt `now` bzw. ihre Eingaben übergeben und
/// ist damit in `KalliTests/` prüfbar.
///
/// Eigene Datei, weil `CalendarStore.swift` mit den Audit-Fixes vom 2026-09-27
/// über die SwiftLint-Sperrklinke (650 Zeilen / 350 Typ-Zeilen) wuchs — laut
/// `.swiftlint.yml` genau der Moment zum Aufteilen. Verschoben, nicht geändert.
extension CalendarStore {

    /// Sammelzustand aus beiden Einzelberechtigungen.
    nonisolated static func access(events: Bool, reminders: Bool) -> Access {
        switch (events, reminders) {
        case (true, true): .granted
        case (false, false): .denied
        default: .partial(events: events, reminders: reminders)
        }
    }

    /// Ist das Setzen des Erledigt-Kennzeichens angekommen?
    ///
    /// **Sonderfall wiederkehrende Erinnerung (Audit-Fund K-C9, 2026-09-27).**
    /// Nach Drittquellen (Entwicklerberichte zu EventKit, **auf Michaels Mac
    /// nicht gemessen**) bleibt beim Abhaken einer Serie `isCompleted` am
    /// selben Objekt `false`; stattdessen rückt die Fälligkeit auf das nächste
    /// Vorkommen. Die Nachprüfung meldete dann fälschlich „Häkchen nicht
    /// angekommen". Defensiv gilt deshalb bei Serien **auch** eine nach vorn
    /// verschobene Fälligkeit als Erfolg — beides wird akzeptiert, weil nicht
    /// gemessen ist, welches Verhalten tatsächlich eintritt. Rückgängig wird
    /// für Serien nicht angeboten: Es träfe womöglich das nächste Vorkommen.
    nonisolated static func completionConfirmed(target: Bool, isCompleted: Bool, recurring: Bool,
                                                dueBefore: Date?, dueAfter: Date?) -> Bool {
        if isCompleted == target { return true }
        guard recurring, target, let dueBefore, let dueAfter else { return false }
        return dueAfter > dueBefore
    }

    /// Gehört der Eintrag an diesen Tag? Reine Funktion, damit prüfbar.
    nonisolated static func occurs(_ item: AgendaItem, on day: Date, calendar: Calendar) -> Bool {
        guard let start = item.start else { return false }
        let dayStart = calendar.startOfDay(for: day)
        if item.isAllDay {
            // Ganztägige Termine haben KEINE Zeitzone. EventKit liefert sie
            // in GMT; mit der lokalen Zeitzone verglichen rutschen sie sonst
            // auf den Vortag. Deshalb wird nur das Kalenderdatum verglichen.
            var utc = calendar
            utc.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
            guard let end = item.end else { return utc.isDate(start, inSameDayAs: day) }
            return start < calendar.date(byAdding: .day, value: 1, to: dayStart)! && end > dayStart
        }
        // Getimte Termine: Überlappung mit dem Tag, nicht nur der Starttag.
        // Bis 2026-09-27 erschien ein Nachtdienst 22–06 nur am ersten Tag
        // (Audit-Fund K-C2). Endet ein Termin exakt um 00:00, gehört er NICHT
        // mehr zum Folgetag (`end > dayStart`). Einträge ohne Dauer
        // (Erinnerungen, end == start) bleiben an ihrem Tag.
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return false }
        let end = max(item.end ?? start, start)
        if end == start { return start >= dayStart && start < nextDay }
        return start < nextDay && end > dayStart
    }

    /// Der nächste noch nicht begonnene Termin.
    ///
    /// Bei gleicher Startzeit gewinnt der **kürzere**: „P&O 10:00–10:30" ist
    /// konkreter als „Abfrage 10:00–12:00". Ein `items.first` nahm hier, was
    /// EventKit zufällig zuerst lieferte.
    ///
    /// `now` wird übergeben statt intern gelesen, damit die Entscheidung ohne
    /// Uhr und ohne EventKit prüfbar ist.
    nonisolated static func nextEvent(in items: [AgendaItem], now: Date) -> AgendaItem? {
        items
            .filter { item in
                guard case .event = item.kind, !item.isAllDay,
                      let start = item.start else { return false }
                return start > now
            }
            .min { lhs, rhs in
                let ls = lhs.start ?? .distantFuture
                let rs = rhs.start ?? .distantFuture
                if ls != rs { return ls < rs }
                return (lhs.end ?? .distantFuture) < (rhs.end ?? .distantFuture)
            }
    }

    /// Der laufende Termin für die Fortschrittsanzeige.
    ///
    /// Drei Einschränkungen, jede aus einem echten Befund:
    ///   1. Ganztägige laufen per Definition den ganzen Tag — ein Fortschritt
    ///      daran wäre die Uhrzeit, keine Information über den Termin.
    ///   2. Termine über `maxHours` sind eher Zustände als Termine (Urlaub,
    ///      Bereitschaft) — ein Prozentwert darauf ist Rauschen. Diese Grenze
    ///      schließt auch den Befund vom 2026-09-21 aus (ein mehrtägiger Termin
    ///      von *gestern* galt als laufend).
    ///   3. Laufen **mehrere** gleichzeitig, gewinnt der, der **zuerst endet**.
    ///      `items.first` nahm den frühesten Start — und damit bei
    ///      „Praxis 08:00–16:00" acht Stunden lang die Praxis, obwohl um 10:00
    ///      ein 30-Minuten-Termin darin lag (Befund 2026-09-22). Wer wissen
    ///      will, wann er wieder frei ist, meint den nächsten Endzeitpunkt.
    ///
    /// **Bis 2026-09-27 gab es eine vierte Regel: „heute begonnen".** Neben der
    /// Dauergrenze wirkte sie nur noch auf kurze Termine über Mitternacht — und
    /// genau die liefen dann unsichtbar: Ein Nachtdienst 22–06 galt um 03:00
    /// nicht als laufend (Audit-Fund K-C2). Die Regel ist jetzt „läuft gerade
    /// und dauert höchstens `maxHours`".
    nonisolated static func runningEvent(in items: [AgendaItem], now: Date,
                                         maxHours: Double) -> AgendaItem? {
        items
            .filter { item in
                guard case .event = item.kind, !item.isAllDay,
                      let start = item.start, let end = item.end else { return false }
                guard start <= now, end > now else { return false }
                return end.timeIntervalSince(start) <= maxHours * 3600
            }
            .min { ($0.end ?? .distantFuture) < ($1.end ?? .distantFuture) }
    }

    /// Der Zustand **einer** Berechtigung, frisch von macOS gelesen.
    ///
    /// Gleiche Haltung wie bei `LoginItem`: Der wahre Zustand liegt bei macOS,
    /// nicht bei uns. Ein gespiegelter Wert wird beim ersten Eingriff von außen
    /// falsch — der Nutzer kann den Zugriff jederzeit in den
    /// Systemeinstellungen entziehen, ohne dass Kalli davon erfährt.
    enum Permission: Equatable {
        /// Noch nie gefragt — **nur hier** kann ein Anfragen etwas bewirken.
        case notDetermined
        case granted
        /// Abgelehnt. macOS fragt danach **nie wieder**; der einzige Weg zurück
        /// sind die Systemeinstellungen.
        case denied
        /// Durch Geräteverwaltung gesperrt. Nicht durch den Nutzer änderbar.
        case restricted

        var label: String {
            switch self {
            case .notDetermined: "noch nicht gefragt"
            case .granted: "erteilt"
            case .denied: "abgelehnt"
            case .restricted: "gesperrt (Geräteverwaltung)"
            }
        }
    }

    nonisolated static func permission(_ status: EKAuthorizationStatus) -> Permission {
        switch status {
        case .notDetermined: .notDetermined
        case .fullAccess: .granted
        case .denied: .denied
        case .restricted: .restricted
        // `writeOnly` gibt es nur fuer Kalender und reicht Kalli nicht — es
        // liest ausschliesslich. Als "abgelehnt" behandeln, damit die Anzeige
        // nicht "erteilt" behauptet, waehrend die Liste leer bleibt.
        case .writeOnly: .denied
        @unknown default: .denied
        }
    }

    /// Rückblick `maxRunningHours` (länger laufende Termine zeigt die Leiste
    /// ohnehin nicht), Vorausblick wie der Mitteilungs-Horizont.
    nonisolated static func barWindow(now: Date) -> DateInterval {
        DateInterval(start: now.addingTimeInterval(-maxRunningHours * 3600),
                     end: now.addingTimeInterval(alertHorizon))
    }

    /// Reine Fassung — ohne `EKEvent`, damit sie prüfbar ist. Ein unsaved
    /// `EKEvent` hat keine setzbare `eventIdentifier`; der interessante Fall
    /// (gleiche ID, verschiedene Startzeit) wäre über EventKit nicht
    /// konstruierbar.
    nonisolated static func eventID(base: String?, start: Date?) -> String {
        let id = base ?? UUID().uuidString
        guard let start else { return id }
        return "\(id)|\(Int(start.timeIntervalSince1970))"
    }

    /// Welche ausgeblendeten IDs nach dem Einlesen der Quellen bleiben.
    ///
    /// Review-Fund 2026-09-27: `loadSources()` sieht nur Kalender der Arten,
    /// für die Zugriff besteht. Bei Teilzugriff (z. B. Erinnerungen entzogen)
    /// hätte der Abgleich die ausgeblendeten Listen der ANDEREN Art still
    /// gelöscht — und mit `refreshAccess()` bei jedem Popover-Öffnen.
    ///
    /// Abgeglichen wird deshalb nur bei Zugriff auf **beide** Arten. „Nur die
    /// IDs dieser Art" geht nicht: Eine gespeicherte ID trägt ihre Art nicht
    /// mit, und eine Liste ohne Zugriff ist über EventKit nicht auffindbar.
    /// Eine veraltete ID überlebt damit höchstens bis zum nächsten Vollzugriff.
    nonisolated static func hiddenAfterPrune(_ hidden: Set<String>, found: Set<String>,
                                             eventsReadable: Bool, remindersReadable: Bool) -> Set<String> {
        guard eventsReadable && remindersReadable else { return hidden }
        return hidden.intersection(found)
    }

    /// Was die Leiste zeigt — ausschließlich aus dem Leisten-Fenster
    /// (`barItems`), nie aus dem Popover-Monat (K-C5).
    nonisolated static func barState(from barItems: [AgendaItem], now: Date)
        -> (next: AgendaItem?, running: AgendaItem?) {
        (nextEvent(in: barItems, now: now),
         runningEvent(in: barItems, now: now, maxHours: maxRunningHours))
    }
}
