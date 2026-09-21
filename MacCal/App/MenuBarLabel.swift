import AppKit
import Foundation
import Observation

/// Liefert den Text für die Menüleiste und hält ihn aktuell.
///
/// Eigener Typ statt `TimelineView` im Label: Das Label einer `MenuBarExtra`
/// wird nicht zuverlässig neu gezeichnet, wenn nur die Zeit vergeht. Ein Timer,
/// der eine beobachtete Eigenschaft setzt, tut es verlässlich.
@MainActor
@Observable
final class MenuBarLabel {

    private(set) var text: String = ""
    /// Das Kalenderblatt-Symbol. Wird mitgeführt, weil die Tageszahl darin steckt.
    private(set) var icon: NSImage = MenuBarIcon.image(day: 1)
    /// Ob das Symbol gezeichnet wird. Erzwungen, wenn sonst nichts übrig bliebe.
    private(set) var showIcon: Bool = true

    private let prefs: Preferences
    private let store: CalendarStore
    private var timer: Timer?

    private let dateFormatter = DateFormatter()
    private let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        return f
    }()

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "HH:mm"
        return f
    }()

    init(prefs: Preferences, store: CalendarStore) {
        self.prefs = prefs
        self.store = store
        dateFormatter.locale = Locale(identifier: "de_DE")
        update()

        // Minütlich reicht: Datum und „nächster Termin" ändern sich nicht
        // schneller. Sekundengenaues Ticken würde nur Strom kosten.
        let t = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.store.refreshNextEvent()
                self?.update()
            }
        }
        t.tolerance = 10
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    // Kein deinit: Ein `deinit` ist nonisolated und darf MainActor-isolierte
    // Eigenschaften nicht anfassen. Der Ausweg `nonisolated(unsafe)` wäre
    // wieder eine Behauptung statt eines Beweises — genau das Muster, das bei
    // Tippi 2.11.5 einen Absturz ausgeliefert hat.
    //
    // Nötig ist es auch nicht: Diese Instanz lebt so lange wie die App. Der
    // Timer hält `self` schwach, läuft also selbst im theoretischen Fall einer
    // Freigabe ins Leere statt auf ein totes Objekt.
    func stop() { timer?.invalidate(); timer = nil }

    func update() {
        let now = Date()
        let day = Calendar.current.component(.day, from: now)
        if currentIconDay != day {
            icon = MenuBarIcon.image(day: day)
            currentIconDay = day
        }

        var parts: [String] = []
        showIcon = prefs.showIconInMenuBar || prefs.menuBarWouldBeEmpty
        if prefs.showDateInMenuBar {
            dateFormatter.dateFormat = prefs.menuBarDateFormat
            parts.append(dateFormatter.string(from: now))
        }
        // Laufender Termin hat Vorrang: was jetzt passiert, schlaegt was kommt.
        if prefs.showRunningProgress, let running = store.runningEvent,
           let remaining = running.remainingLabel() {
            let sep = parts.isEmpty ? "" : "· "
            parts.append("\(sep)\(shorten(running.title)) \(remaining)")
        } else if prefs.showNextEventInMenuBar, let next = store.nextEvent, let start = next.start {
            let sep = parts.isEmpty ? "" : "· "
            // Tag voranstellen, wenn der Termin nicht heute ist. Ohne das liest
            // sich "08:00 Praxis" um 15 Uhr wie ein laufender Termin, obwohl es
            // der von morgen früh ist.
            let dayPrefix: String
            if Calendar.current.isDateInToday(start) {
                dayPrefix = ""
            } else if Calendar.current.isDateInTomorrow(start) {
                dayPrefix = "morgen "
            } else {
                weekdayFormatter.dateFormat = "EEE"
                dayPrefix = weekdayFormatter.string(from: start) + " "
            }
            parts.append("\(sep)\(dayPrefix)\(timeFormatter.string(from: start)) \(shorten(next.title))")
        }
        text = parts.joined(separator: " ")
    }

    /// Damit das Symbol nur beim echten Tageswechsel neu gezeichnet wird und
    /// nicht sechzigmal pro Stunde.
    private var currentIconDay: Int = 0

    /// Kürzt den Titel auf eine feste Länge.
    ///
    /// Ohne Deckel springt die Breite des Menüleisten-Eintrags bei jedem
    /// Terminwechsel, und alle Symbole rechts davon hüpfen mit.
    private func shorten(_ title: String) -> String {
        let limit = max(6, prefs.nextEventMaxChars)
        guard title.count > limit else { return title }
        return title.prefix(limit - 1).trimmingCharacters(in: .whitespaces) + "…"
    }
}
