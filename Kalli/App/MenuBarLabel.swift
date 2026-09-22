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

        // Der Anstoss zum ersten Laden gehoert hierhin, weil dies das einzige
        // Objekt ist, das vor dem ersten Oeffnen des Popovers lebt. Ohne ihn
        // bleibt die Leiste bis zum ersten Klick leer — siehe
        // CalendarStore.loadIfAlreadyAuthorized().
        Task { @MainActor [weak self] in
            guard let self else { return }
            await self.store.loadIfAlreadyAuthorized()
            self.update()
        }
    }

    // Kein deinit: Ein `deinit` ist nonisolated und darf MainActor-isolierte
    // Eigenschaften nicht anfassen. Der Ausweg `nonisolated(unsafe)` wäre
    // wieder eine Behauptung statt eines Beweises — genau das Muster, das bei
    // Tippi 2.11.5 einen Absturz ausgeliefert hat.
    //
    // Nötig ist es auch nicht: Diese Instanz lebt so lange wie die App. Der
    // Timer hält `self` schwach, läuft also selbst im theoretischen Fall einer
    // Freigabe ins Leere statt auf ein totes Objekt.
    func stop() {
        timer?.invalidate(); timer = nil
        pulseTimer?.invalidate(); pulseTimer = nil
    }

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
        // Was KOMMT schlaegt was LAEUFT — sobald es in Vorlaufzeit ist.
        //
        // Bis 2026-09-22 war es umgekehrt (ein `else if`): ein laufender Termin
        // verdraengte den naechsten vollstaendig. Bei "Praxis 08:00–16:00" hiess
        // das acht Stunden Fortschrittsbalken, waehrend zwei Termine um 10:00
        // die Leiste nie erreichten (Befund von Michael, 2026-09-22). Die
        // Leiste ist knapp; sie muss das Handlungsrelevante zeigen, und das ist
        // der naechste Termin. Der Fortschritt des Laufenden steht weiter im
        // Popover, wo Platz dafuer ist.
        if let part = Self.eventPart(showEvent: prefs.showNextEventInMenuBar,
                                     showProgress: prefs.showRunningProgress,
                                     next: nextEventPart(),
                                     running: runningEventPart()) {
            let sep = parts.isEmpty ? "" : "· "
            parts.append("\(sep)\(part)")
        }
        // Der Puls steht ganz vorn, damit er auch bei ausgeschaltetem Datum
        // und ausgeschaltetem Termintext noch sichtbar ist.
        text = pulseMarker() + parts.joined(separator: " ")
        syncPulseTimer()
    }

    /// Welcher Termintext gehört in die Leiste — oder **keiner**.
    ///
    /// **Der Fund vom 2026-09-22 (Michael):** „Wenn man *Nächsten Termin
    /// anzeigen* abwählt, wird der aktuelle angezeigt. Es muss aber auswählbar
    /// sein, dass gar kein Termin angezeigt wird."
    ///
    /// Zu Recht, und die Ursache ist meine eigene Änderung aus 0.1.1. Vorher
    /// hing der laufende Termin allein an `showRunningProgress`, der nächste
    /// allein an `showNextEventInMenuBar` — mit dem `?? `-Rückfall von 0.1.1
    /// überlebte der laufende Termin das Abwählen des nächsten. Und
    /// `showRunningProgress` abzuschalten war kein Ausweg: Das nimmt auch den
    /// Fortschrittsbalken **im Popover** weg.
    ///
    /// Damit war die Beschriftung seit 0.1.1 unwahr — sie sprach vom „nächsten
    /// Termin" und zeigte auch den laufenden. Der Schalter heißt jetzt
    /// „Termin in der Leiste anzeigen" und schaltet **beides**.
    ///
    /// Regel, hier an einer Stelle und ohne Seiteneffekte prüfbar:
    ///   1. Schalter aus → **nichts**, egal was läuft.
    ///   2. Sonst: der nächste Termin, wenn einer in Vorlaufzeit ist.
    ///   3. Sonst der laufende — aber nur, wenn der Fortschritt eingeschaltet ist.
    nonisolated static func eventPart(showEvent: Bool, showProgress: Bool,
                                      next: String?, running: String?) -> String? {
        guard showEvent else { return nil }
        if let next { return next }
        guard showProgress else { return nil }
        return running
    }

    /// Der naechste Termin, aber erst ab der eingestellten Vorlaufzeit.
    ///
    /// Ein Termin, der in fuenf Stunden beginnt, ist in einer stets sichtbaren
    /// Leiste kein Hinweis, sondern Belegung.
    private func nextEventPart() -> String? {
        guard prefs.showNextEventInMenuBar,
              let next = store.nextEvent,
              let start = next.start,
              start.timeIntervalSinceNow <= Double(prefs.menuBarLeadMinutes) * 60
        else { return nil }

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
        // Countdown dazu, aber nur fuer heute. "morgen 08:00 Praxis in 22:15
        // Std." waere eine Zahl, die niemand liest — der Tagesname sagt es
        // schon. Heute ist "in 13 Min." dagegen das, was die Entscheidung
        // traegt: aufstehen oder weiterarbeiten.
        let countdown: String
        if Calendar.current.isDateInToday(start), let inLabel = next.startsInLabel() {
            countdown = " " + inLabel
        } else {
            countdown = ""
        }
        return "\(dayPrefix)\(timeFormatter.string(from: start)) \(shorten(next.title))\(countdown)"
    }

    /// Der laufende Termin mit Restzeit. Die Schalter-Prüfung liegt bewusst in
    /// `eventPart(...)` und nicht hier — an einer Stelle, prüfbar.
    private func runningEventPart() -> String? {
        guard let running = store.runningEvent,
              let remaining = running.remainingLabel()
        else { return nil }
        return "\(shorten(running.title)) \(remaining)"
    }

    // MARK: - Puls vor dem nächsten Termin

    /// Ob der Puls gerade „an" ist. Wechselt im Sekundentakt.
    private var pulseOn = false
    private var pulseTimer: Timer?

    /// Liegt der nächste Termin im Vorlauffenster des prominenten Hinweises?
    ///
    /// Bewusst unabhaengig von `showNextEventInMenuBar`: Der Puls ist ein
    /// eigener Kanal. Wer den Termintext abgeschaltet hat, aber gewarnt werden
    /// will, bekommt den Punkt trotzdem.
    private var isInAlertWindow: Bool {
        guard prefs.flashNextEventInMenuBar,
              let start = store.nextEvent?.start else { return false }
        let remaining = start.timeIntervalSinceNow
        return remaining > 0 && remaining <= Double(prefs.alertLeadMinutes) * 60
    }

    /// „● " bzw. „○ " im Wechsel — oder nichts außerhalb des Fensters.
    ///
    /// **Gleiche Laufweite fuer beide Zeichen.** Ein Wechsel zwischen „Zeichen"
    /// und „kein Zeichen" liesse die Breite der Leiste im Sekundentakt springen,
    /// und alle Symbole rechts davon huepften mit — dieselbe Falle, gegen die
    /// `shorten(_:)` den Titel deckelt.
    private func pulseMarker() -> String {
        guard isInAlertWindow else { return "" }
        return pulseOn ? "● " : "○ "
    }

    /// Startet den Sekundentakt nur im Vorlauffenster und raeumt ihn danach ab.
    ///
    /// Ein dauerhaft laufender Sekundentimer waere Strom fuer nichts — der
    /// Minutentimer reicht fuer alles ausserhalb dieses Fensters.
    private func syncPulseTimer() {
        if isInAlertWindow {
            guard pulseTimer == nil else { return }
            let t = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.pulseOn.toggle()
                    self.update()
                }
            }
            t.tolerance = 0.1
            RunLoop.main.add(t, forMode: .common)
            pulseTimer = t
        } else if pulseTimer != nil {
            pulseTimer?.invalidate()
            pulseTimer = nil
            pulseOn = false
        }
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
