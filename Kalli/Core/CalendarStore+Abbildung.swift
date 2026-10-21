import EventKit
import Foundation

/// EventKit-Objekte → `AgendaItem`/`RGBA` (Abbildung, ohne Zustand).
///
/// Eigene Datei aus demselben Grund wie `CalendarStore+Regeln`: Mit 0.10.0 (neue
/// Erinnerung, dringende Erinnerungen im Vollbild) wuchs `CalendarStore.swift` wieder über
/// die SwiftLint-Sperrklinke (650 Zeilen / 350 Typ-Zeilen). Verschoben, nicht geändert —
/// nur `private` fiel weg, damit die Klasse sie aus der anderen Datei erreicht.
extension CalendarStore {

    /// `nonisolated`, weil diese Funktion auch aus EventKit-Callbacks auf
    /// fremden Queues gerufen wird. Ohne das Schlüsselwort wäre sie
    /// MainActor-isoliert — `static` in einer `@MainActor`-Klasse erbt die
    /// Isolation — und der Aufruf von der falschen Queue aus wäre ein Absturz.
    nonisolated static func rgba(from cal: EKCalendar) -> RGBA {
        guard let comps = cal.cgColor?.components, comps.count >= 3 else { return .fallback }
        return RGBA(r: Double(comps[0]), g: Double(comps[1]), b: Double(comps[2]),
                    a: Double(comps.count >= 4 ? comps[3] : 1))
    }

    /// `EKEvent` → `AgendaItem`. Eine Stelle, damit die Kennung nicht an zwei
    /// Orten unterschiedlich gebildet wird.
    nonisolated static func mapEvent(_ ev: EKEvent) -> AgendaItem {
        AgendaItem(
            // **Kennung aus Termin-ID UND Startzeit.** `eventIdentifier` ist bei
            // Serienterminen laut EventKit-Vertrag für ALLE Vorkommen identisch.
            // Mit der ID allein kollidieren zwei Vorkommen desselben Termins:
            // `ForEach` bekäme doppelte IDs (unbestimmtes Rendering), und eine
            // Mitteilung pro Vorkommen wäre unmöglich, weil jede die vorige mit
            // gleicher Kennung ersetzt. Fällt bei täglichen Serien nicht auf,
            // bei "alle 4 Stunden" sofort. (Audit 2026-09-22.)
            id: Self.eventID(ev),
            title: ev.title ?? "(ohne Titel)",
            start: ev.startDate,
            end: ev.endDate,
            isAllDay: ev.isAllDay,
            hasTime: !ev.isAllDay,
            kind: .event,
            sourceID: ev.calendar?.calendarIdentifier ?? "",
            color: ev.calendar.map(rgba) ?? .fallback,
            hasAlarms: ev.hasAlarms,
            link: MeetingLink.find(url: ev.url, location: ev.location, notes: ev.notes),
            isDeclined: ev.attendees?.first(where: \.isCurrentUser)?.participantStatus == .declined
        )
    }

    nonisolated static func eventID(_ ev: EKEvent) -> String {
        eventID(base: ev.eventIdentifier, start: ev.startDate)
    }

    /// Wandelt EKReminder in `Sendable`-Werte um. Läuft auf EventKits Queue.
    ///
    /// Muss `nonisolated` sein — siehe Absturz vom 2026-09-21 beim ersten
    /// Erteilen der Berechtigung: `_dispatch_assert_queue_fail` im compactMap,
    /// weil das Closure die MainActor-Isolation der Klasse geerbt hatte. Ein
    /// Kommentar „überquert die Isolationsgrenze nie" ist eine Behauptung;
    /// `nonisolated` ist die Zusicherung, die der Compiler prüfen kann.
    nonisolated static func mapReminders(
        _ reminders: [EKReminder]?, range: DateInterval
    ) -> [AgendaItem] {
        (reminders ?? []).compactMap { rem in
            // Ohne Fälligkeitsdatum gehört eine Erinnerung an keinen Tag im
            // Raster. Sie zu behalten hieße, sie entweder an jedem Tag oder an
            // gar keinem zu zeigen — beides falsch.
            guard let comps = rem.dueDateComponents,
                  let due = comps.date,
                  due >= range.start, due < range.end else { return nil }
            // hour == nil heißt: nur ein Tag gesetzt, keine Uhrzeit.
            let hasClockTime = comps.hour != nil
            return AgendaItem(
                id: rem.calendarItemIdentifier,
                title: rem.title ?? "(ohne Titel)",
                start: due,
                end: nil,
                // Eine Erinnerung ohne Uhrzeit ist kein Ganztagstermin, sondern
                // hat schlicht keine Zeit. Sie erscheint unten in der Tagesliste.
                isAllDay: false,
                hasTime: hasClockTime,
                kind: .reminder(completed: rem.isCompleted),
                sourceID: rem.calendar?.calendarIdentifier ?? "",
                color: rem.calendar.map(rgba) ?? .fallback,
                hasAlarms: rem.hasAlarms,
                isRecurring: rem.hasRecurrenceRules,
                isUrgent: QuickReminder.isHighPriority(rem.priority)
            )
        }
    }
}
