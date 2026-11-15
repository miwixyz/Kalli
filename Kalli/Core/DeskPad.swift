import Foundation

/// Reine Logik des Schreibtisch-Blatts (0.14.0, Michael 2026-11-15: ein Tagesblatt auf dem
/// Desktop „wie Daypad", dazu Termine und Aufgaben). Hier steht nur, was sich ohne Fenster
/// und ohne EventKit prüfen lässt.
enum DeskPad {

    /// Eine Gruppe des Blatts. Leere Gruppen gibt es nicht — das Blatt hat kein „+".
    struct Section: Identifiable, Equatable {
        let kind: AgendaGroupKind
        let items: [AgendaItem]
        var id: AgendaGroupKind { kind }
    }

    /// Teilt die Einträge eines Tages in dieselben drei Gruppen und dieselbe Reihenfolge wie
    /// die Tagesliste im Popover (`Preferences.agendaOrder`).
    ///
    /// Erledigte Erinnerungen bleiben nur, wenn „Erledigte anzeigen" gilt — oder sie wurden
    /// gerade abgehakt (`keeping`): Eine Zeile, die im Moment des Klicks verschwindet, sieht
    /// aus wie ein Fehlklick (gleiche Regel wie im Popover).
    static func sections(from items: [AgendaItem],
                         order: [AgendaGroupKind],
                         showCompleted: Bool,
                         keeping: Set<String> = []) -> [Section] {
        let shown = items.filter { showCompleted || !$0.isCompleted || keeping.contains($0.id) }
        let byKind: [AgendaGroupKind: [AgendaItem]] = [
            .allDay: shown.filter { $0.isAllDay && !$0.isReminder },
            .timed: shown.filter { !$0.isAllDay && !$0.isReminder },
            .tasks: shown.filter(\.isReminder),
        ]
        return AgendaGroupKind.normalized(order).compactMap { kind in
            guard let list = byKind[kind], !list.isEmpty else { return nil }
            return Section(kind: kind, items: list)
        }
    }

    /// Tag um `days` verschoben, immer auf 00:00 Ortszeit. Ohne Ergebnis bleibt der Tag stehen.
    static func shifted(_ day: Date, by days: Int, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: day)
        return calendar.date(byAdding: .day, value: days, to: start) ?? start
    }
}
