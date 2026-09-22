import AppKit
import EventKit
import Foundation
import OSLog
import Observation

/// Liest Termine und Erinnerungen.
///
/// **Schreibend nur an genau einer Stelle:** `setCompleted(_:for:)` setzt das
/// Erledigt-Kennzeichen einer Erinnerung. Sonst nichts — keine Termine anlegen,
/// keine Titel ändern, nichts löschen. Die Einschränkung ist Absicht und in
/// `RECHTLICHES.md` zugesagt; wer sie erweitert, muss dort nachziehen.
@MainActor
@Observable
final class CalendarStore {

    enum Access: Equatable {
        case unknown
        case granted
        case denied
        case partial(events: Bool, reminders: Bool)
    }

    private(set) var access: Access = .unknown
    private(set) var sources: [SourceInfo] = []
    private(set) var items: [AgendaItem] = []
    /// Der nächste noch nicht begonnene Termin (keine Erinnerung, nicht ganztägig).
    private(set) var nextEvent: AgendaItem?
    /// Der Termin, der gerade läuft. Für die Fortschrittsanzeige.
    private(set) var runningEvent: AgendaItem?

    /// Längste Dauer, für die ein Fortschritt sinnvoll ist.
    private static let maxRunningHours: Double = 12

    /// Messpunkt fuer das Abhaken. Von aussen lesbar mit:
    ///
    ///     log show --last 15m --predicate 'subsystem == "com.kalli.app"' --info
    ///
    /// Gebaut am 2026-09-22, nachdem Michael meldete, dass abgehakte Aufgaben
    /// nicht in Apple Erinnerungen ankommen. Die App hatte dazu nichts zu
    /// sagen: `save()` lief ohne Fehler durch, und danach prueft niemand, ob
    /// das Kennzeichen wirklich steht. Drei Vermutungen ohne Messung sind eine
    /// zu viel — also erst messen.
    nonisolated private static let log = Logger(subsystem: "com.kalli.app", category: "erinnerungen")

    private let store = EKEventStore()
    private let alerts = EventAlerts()
    private var observer: NSObjectProtocol?
    private var loadedRange: DateInterval?

    private let prefs: Preferences

    init(prefs: Preferences) {
        self.prefs = prefs
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: store, queue: .main
        ) { [weak self] _ in
            // Kein assumeIsolated: der Aufruf landet über .main zwar auf dem
            // Hauptthread, aber "Hauptthread" und "MainActor-isoliert" sind für
            // den Compiler nicht dasselbe. Task @MainActor sagt die Wahrheit.
            Task { @MainActor [weak self] in
                await self?.reload()
            }
        }
    }

    // Kein deinit — gleiche Begründung wie in MenuBarLabel: nonisolated deinit
    // kommt an MainActor-Eigenschaften nicht heran, und die Instanz lebt so
    // lange wie die App. Der Block hält `self` schwach.
    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
    }

    // MARK: - Berechtigung

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

    nonisolated var eventPermission: Permission {
        Self.permission(EKEventStore.authorizationStatus(for: .event))
    }

    nonisolated var reminderPermission: Permission {
        Self.permission(EKEventStore.authorizationStatus(for: .reminder))
    }

    /// Kann ein Anfragen überhaupt etwas bewirken?
    ///
    /// **Der Kern des Fehlers vom 2026-09-22:** Bis dahin fragte die App nur,
    /// wenn `access == .unknown` war. `loadIfAlreadyAuthorized()` setzte aber
    /// `.partial(events: true, reminders: false)`, sobald *eine* der beiden
    /// Berechtigungen schon erteilt war — und damit wurde die **fehlende nie
    /// angefragt**. Angezeigt wurde `.partial` auch nicht (der Hinweis im
    /// Popover hing an `.denied`). Michael: „Die Kalender-Berechtigung wird
    /// nicht mehr abgefragt und es gibt keine Möglichkeit in der App das zu
    /// überprüfen und neu anzustoßen." Beides stimmte.
    ///
    /// Gefragt wird jetzt nach dem, was zählt: Steht irgendeine der beiden auf
    /// `notDetermined`? Nur dann kann ein Dialog erscheinen.
    /// Protokolliert, dass das Popover geöffnet wurde — und ob daraus eine
    /// Anfrage folgte. Ohne diese Zeile sieht „nichts passiert" genauso aus wie
    /// „nichts wurde versucht".
    nonisolated static func logPopoverOpened(canPrompt: Bool) {
        log.notice("POPOVER geoeffnet — canPrompt \(canPrompt, privacy: .public)")
    }

    nonisolated var canPrompt: Bool {
        eventPermission == .notDetermined || reminderPermission == .notDetermined
    }

    /// Fehlt etwas, das Kalli braucht?
    nonisolated var permissionsIncomplete: Bool {
        eventPermission != .granted || reminderPermission != .granted
    }

    /// Öffnet die Systemeinstellungen an der richtigen Stelle — der einzige Weg
    /// zurück, wenn eine Berechtigung abgelehnt wurde.
    nonisolated static func openPrivacySettings(reminders: Bool = false) {
        let pane = reminders ? "Privacy_Reminders" : "Privacy_Calendars"
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Fragt die Berechtigungen an — und **protokolliert, was tatsächlich
    /// passiert ist**.
    ///
    /// Messpunkt gebaut am 2026-09-22, nachdem Michael meldete: „Abfrage ist da,
    /// es geschieht nach Klick aber nichts." Ob macOS keinen Dialog zeigt, ob
    /// die Anfrage fehlschlägt oder ob nur die Anzeige nicht nachzieht, ist von
    /// außen nicht unterscheidbar — und Raten hat heute mehrfach nicht
    /// funktioniert. Lesbar mit:
    ///
    ///     log show --last 10m --predicate 'subsystem == "com.kalli.app"'
    ///
    /// Der Rückgabewert sagt, ob sich **überhaupt etwas geändert** hat. Die
    /// Oberfläche kann damit „macOS hat keinen Dialog gezeigt" anzeigen statt
    /// stumm gleich auszusehen.
    @discardableResult
    func requestAccess() async -> Bool {
        let beforeEvents = eventPermission
        let beforeReminders = reminderPermission
        Self.log.notice("Anfrage startet — Kalender \(beforeEvents.label, privacy: .public), Erinnerungen \(beforeReminders.label, privacy: .public)")

        async let eventsOK = requestEvents()
        async let remindersOK = requestReminders()
        let (e, r) = await (eventsOK, remindersOK)

        let afterEvents = eventPermission
        let afterReminders = reminderPermission
        Self.log.notice("Anfrage beendet — Rueckgabe Kalender \(e, privacy: .public)/Erinnerungen \(r, privacy: .public), Status jetzt Kalender \(afterEvents.label, privacy: .public), Erinnerungen \(afterReminders.label, privacy: .public)")

        access = switch (e, r) {
        case (true, true): .granted
        case (false, false): .denied
        default: .partial(events: e, reminders: r)
        }

        if e || r {
            loadSources()
            await reload()
        }

        let changed = afterEvents != beforeEvents || afterReminders != beforeReminders
        if !changed { Self.log.error("Nichts hat sich geaendert. Entweder hat macOS keinen Dialog gezeigt, oder er wurde weggeklickt.") }
        return changed
    }

    private func requestEvents() async -> Bool {
        do { return try await store.requestFullAccessToEvents() } catch { return false }
    }

    private func requestReminders() async -> Bool {
        do { return try await store.requestFullAccessToReminders() } catch { return false }
    }

    // MARK: - Quellen (Kalender + Erinnerungslisten)

    private func loadSources() {
        var found: [SourceInfo] = []

        for cal in store.calendars(for: .event) {
            found.append(SourceInfo(
                id: cal.calendarIdentifier,
                title: cal.title,
                color: Self.rgba(from: cal),
                kind: .event,
                sourceTitle: cal.source?.title ?? "Lokal"
            ))
        }
        for cal in store.calendars(for: .reminder) {
            found.append(SourceInfo(
                id: cal.calendarIdentifier,
                title: cal.title,
                color: Self.rgba(from: cal),
                kind: .reminder,
                sourceTitle: cal.source?.title ?? "Lokal"
            ))
        }

        sources = found.sorted {
            ($0.sourceTitle, $0.title) < ($1.sourceTitle, $1.title)
        }
        prefs.pruneHidden(to: Set(found.map(\.id)))
    }

    /// `nonisolated`, weil diese Funktion auch aus EventKit-Callbacks auf
    /// fremden Queues gerufen wird. Ohne das Schlüsselwort wäre sie
    /// MainActor-isoliert — `static` in einer `@MainActor`-Klasse erbt die
    /// Isolation — und der Aufruf von der falschen Queue aus wäre ein Absturz.
    nonisolated private static func rgba(from cal: EKCalendar) -> RGBA {
        guard let comps = cal.cgColor?.components, comps.count >= 3 else { return .fallback }
        return RGBA(r: Double(comps[0]), g: Double(comps[1]), b: Double(comps[2]),
                    a: Double(comps.count >= 4 ? comps[3] : 1))
    }

    // MARK: - Laden

    /// Lädt den sichtbaren Monat plus Rand, damit das Raster vollständig ist.
    func load(month: Date, calendar: Calendar) async {
        guard let monthStart = calendar.dateInterval(of: .month, for: month)?.start,
              let monthEnd = calendar.dateInterval(of: .month, for: month)?.end else { return }
        let from = calendar.date(byAdding: .day, value: -7, to: monthStart) ?? monthStart
        let to = calendar.date(byAdding: .day, value: 7, to: monthEnd) ?? monthEnd
        loadedRange = DateInterval(start: from, end: to)
        await reload()
    }

    func reload() async {
        guard let range = loadedRange else { return }
        var collected = await fetchEvents(in: range)
        collected += await fetchReminders(in: range)
        items = collected.sorted { lhs, rhs in
            (lhs.start ?? .distantFuture) < (rhs.start ?? .distantFuture)
        }
        recomputeNextEvent()
        await syncAlerts()
    }

    // MARK: - Mitteilungen

    /// Bringt die geplanten Systemmitteilungen auf den Stand der Termine.
    /// Idempotent — darf jederzeit doppelt laufen.
    func syncAlerts() async {
        // Erst prüfen, DANN abfragen. `reload()` läuft bei jeder
        // EventKit-Änderung und bei jedem Monatswechsel; eine
        // 24-Stunden-Abfrage, deren Ergebnis anschließend verworfen wird, ist
        // Arbeit für nichts. (Beim Re-Audit des eigenen Fixes gefunden,
        // 2026-09-22.)
        guard prefs.notifyBeforeNextEvent else {
            await alerts.sync(horizon: [], enabled: false,
                              leadMinutes: prefs.alertLeadMinutes)
            return
        }
        // Bewusst NICHT `items`: siehe fetchAlertHorizon().
        await alerts.sync(
            horizon: await fetchAlertHorizon(),
            enabled: true,
            leadMinutes: prefs.alertLeadMinutes
        )
    }

    /// Fragt die Mitteilungs-Berechtigung an. Gibt zurück, ob sie **danach
    /// tatsächlich vorliegt** — nicht, ob der Aufruf durchlief.
    func requestNotificationPermission() async -> Bool {
        await alerts.requestPermission()
    }

    private func fetchEvents(in range: DateInterval) async -> [AgendaItem] {
        await fetchEvents(from: range.start, to: range.end)
    }

    /// Holt Termine in einem Zeitfenster. Eine Stelle für beide Aufrufer —
    /// Monatsansicht und Mitteilungs-Horizont.
    private func fetchEvents(from: Date, to: Date) async -> [AgendaItem] {
        let cals = store.calendars(for: .event).filter { !prefs.isHidden($0.calendarIdentifier) }
        guard !cals.isEmpty else { return [] }

        let predicate = store.predicateForEvents(withStart: from, end: to, calendars: cals)
        // Wiederkehrende Termine werden hier NICHT selbst aufgelöst. EventKit
        // expandiert sie inklusive Ausnahmen und verschobener Einzeltermine.
        // Wer das selbst rechnet, baut sich Fehler für Monate ein.
        return store.events(matching: predicate).map(Self.mapEvent)
    }

    /// `EKEvent` → `AgendaItem`. Eine Stelle, damit die Kennung nicht an zwei
    /// Orten unterschiedlich gebildet wird.
    nonisolated private static func mapEvent(_ ev: EKEvent) -> AgendaItem {
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
            hasAlarms: ev.hasAlarms
        )
    }

    nonisolated private static func eventID(_ ev: EKEvent) -> String {
        eventID(base: ev.eventIdentifier, start: ev.startDate)
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

    /// Termine der nächsten 24 Stunden — **unabhängig vom geladenen Monat**.
    ///
    /// Grund (Audit 2026-09-22, schwerster Fund): Die Mitteilungs-Planung hing
    /// vorher an `items`, und `items` enthält nur den geladenen Monat ±7 Tage.
    /// Ein Klick auf „nächster Monat" im Popover ließ die heutigen Termine aus
    /// `items` verschwinden — worauf die Planung sie für *gelöscht* hielt und
    /// die bereits geplanten Mitteilungen entfernte. Das Feature schaltete sich
    /// damit still ab, ausgelöst durch eine harmlose Navigation.
    ///
    /// Der Horizont wird deshalb eigens abgefragt. `items` ist eine Ansicht für
    /// die Oberfläche, keine Quelle für Terminexistenz.
    private func fetchAlertHorizon() async -> [AgendaItem] {
        let now = Date()
        return await fetchEvents(from: now, to: now.addingTimeInterval(Self.alertHorizon))
    }

    /// Wie weit voraus Mitteilungen geplant werden.
    private static let alertHorizon: TimeInterval = 24 * 3600

    private func fetchReminders(in range: DateInterval) async -> [AgendaItem] {
        let cals = store.calendars(for: .reminder).filter { !prefs.isHidden($0.calendarIdentifier) }
        guard !cals.isEmpty else { return [] }

        // Bewusst der Alles-Prädikat statt predicateForIncompleteReminders:
        // Letzteres liefert ausschließlich offene Erinnerungen, womit die
        // Einstellung „Erledigte anzeigen" wirkungslos wäre — sie würde eine
        // Liste filtern, in der das Gesuchte nie ankommt. Gefiltert wird
        // stattdessen sichtbar in der View.
        let predicate = store.predicateForReminders(in: cals)

        // fetchReminders ruft seinen Callback auf einer fremden Queue auf.
        return await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                // Nur ein Aufruf einer nonisolated Funktion. Stünde die
                // Umwandlung hier inline, wäre sie MainActor-isoliert (sie
                // steht in einer @MainActor-Klasse) und liefe trotzdem auf
                // EventKits Queue — Swift 6 prüft das zur Laufzeit und bricht ab.
                continuation.resume(returning: Self.mapReminders(reminders, range: range))
            }
        }
    }

    /// Wandelt EKReminder in `Sendable`-Werte um. Läuft auf EventKits Queue.
    ///
    /// Muss `nonisolated` sein — siehe Absturz vom 2026-09-21 beim ersten
    /// Erteilen der Berechtigung: `_dispatch_assert_queue_fail` im compactMap,
    /// weil das Closure die MainActor-Isolation der Klasse geerbt hatte. Ein
    /// Kommentar „überquert die Isolationsgrenze nie" ist eine Behauptung;
    /// `nonisolated` ist die Zusicherung, die der Compiler prüfen kann.
    nonisolated private static func mapReminders(
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
                hasAlarms: rem.hasAlarms
            )
        }
    }

    // MARK: - Schreiben (nur Erledigt-Kennzeichen)

    /// Hakt eine Erinnerung ab oder nimmt das Häkchen zurück.
    ///
    /// Gibt eine Fehlermeldung zurück, statt sie zu schlucken: Ein Häkchen, das
    /// sichtbar gesetzt wird und in Wahrheit nicht ankommt, ist schlimmer als
    /// eine Fehlermeldung — man verlässt sich darauf.
    @discardableResult
    func setCompleted(_ completed: Bool, for item: AgendaItem) async -> String? {
        guard item.isReminder else { return nil }

        // Frisch aus EventKit holen. Das AgendaItem ist eine Momentaufnahme;
        // dazwischen kann die Erinnerung anderswo geändert worden sein.
        guard let reminder = store.calendarItem(withIdentifier: item.id) as? EKReminder else {
            return "Diese Erinnerung gibt es nicht mehr."
        }

        let listName = reminder.calendar?.title ?? "(ohne Liste)"
        reminder.isCompleted = completed
        do {
            try store.save(reminder, commit: true)
        } catch {
            Self.log.error("Speichern fehlgeschlagen — Liste \(listName, privacy: .public), Ziel \(completed, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return error.localizedDescription
        }

        await reload()

        // NACHLESEN STATT GLAUBEN. Ein `save()` ohne Fehler heisst nur: der
        // Aufruf ist durchgelaufen. Ob das Kennzeichen wirklich steht, weiss
        // allein EventKit — und `reload()` hat gerade frisch gelesen.
        //
        // Ohne diese Pruefung meldet die App Erfolg, die Zeile blendet sich
        // nach drei Sekunden aus, und niemand erfaehrt, dass in Apple
        // Erinnerungen nichts angekommen ist. Genau dieser Fall wurde am
        // 2026-09-22 gemeldet.
        guard let fresh = items.first(where: { $0.id == item.id }) else {
            // Kein Beweis moeglich: Die Erinnerung liegt ausserhalb des
            // geladenen Zeitraums. Das ist kein Fehler, aber auch keine
            // Bestaetigung — und wird als das protokolliert, was es ist.
            Self.log.notice("Nicht nachpruefbar — Erinnerung liegt ausserhalb des geladenen Zeitraums. Liste \(listName, privacy: .public), Ziel \(completed, privacy: .public).")
            return nil
        }

        if fresh.isCompleted != completed {
            Self.log.error("Haekchen NICHT angekommen — Liste \(listName, privacy: .public): gesetzt auf \(completed, privacy: .public), zurueckgelesen \(fresh.isCompleted, privacy: .public).")
            return completed
                ? "Das Häkchen ist nicht angekommen — Apple Erinnerungen hat es nicht übernommen."
                : "Das Zurücknehmen ist nicht angekommen — Apple Erinnerungen hat es nicht übernommen."
        }

        Self.log.notice("Haekchen bestaetigt — Liste \(listName, privacy: .public), jetzt \(fresh.isCompleted, privacy: .public).")
        return nil
    }

    // MARK: - Abfragen

    func items(on day: Date, calendar: Calendar) -> [AgendaItem] {
        items.filter { item in
            guard let start = item.start else { return false }
            if item.isAllDay {
                // Ganztägige Termine haben KEINE Zeitzone. EventKit liefert sie
                // in GMT; mit der lokalen Zeitzone verglichen rutschen sie sonst
                // auf den Vortag. Deshalb wird nur das Kalenderdatum verglichen.
                var utc = calendar
                utc.timeZone = TimeZone(secondsFromGMT: 0) ?? calendar.timeZone
                let dayStart = calendar.startOfDay(for: day)
                guard let end = item.end else { return utc.isDate(start, inSameDayAs: day) }
                return start < calendar.date(byAdding: .day, value: 1, to: dayStart)! && end > dayStart
            }
            return calendar.isDate(start, inSameDayAs: day)
        }
    }

    func hasItems(on day: Date, calendar: Calendar) -> Bool {
        !items(on: day, calendar: calendar).isEmpty
    }

    private func recomputeNextEvent() {
        let now = Date()
        nextEvent = Self.nextEvent(in: items, now: now)
        runningEvent = Self.runningEvent(in: items, now: now,
                                         calendar: .current,
                                         maxHours: Self.maxRunningHours)
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
    /// Vier Einschränkungen, jede aus einem echten Befund:
    ///   1. Ganztägige laufen per Definition den ganzen Tag — ein Fortschritt
    ///      daran wäre die Uhrzeit, keine Information über den Termin.
    ///   2. Der Termin muss **am selben Tag wie `now`** begonnen haben.
    ///      `start <= now && end > now` ist formal richtig, trifft aber auch
    ///      mehrtägige Termine, deren Ende zufällig in der Zukunft liegt
    ///      (Befund 2026-09-21: ein Termin von *gestern* galt als laufend).
    ///   3. Termine über `maxHours` sind eher Zustände als Termine (Urlaub,
    ///      Bereitschaft) — ein Prozentwert darauf ist Rauschen.
    ///   4. Laufen **mehrere** gleichzeitig, gewinnt der, der **zuerst endet**.
    ///      `items.first` nahm den frühesten Start — und damit bei
    ///      „Praxis 08:00–16:00" acht Stunden lang die Praxis, obwohl um 10:00
    ///      ein 30-Minuten-Termin darin lag (Befund 2026-09-22). Wer wissen
    ///      will, wann er wieder frei ist, meint den nächsten Endzeitpunkt.
    ///
    /// Zu 2.: Der Vergleich läuft gegen `now`, nicht gegen `isDateInToday`.
    /// Letzteres fragt die Systemuhr und wäre in einem Test mit fest gesetztem
    /// `now` nicht prüfbar — in der Anwendung sind beide identisch.
    nonisolated static func runningEvent(in items: [AgendaItem], now: Date,
                                         calendar: Calendar, maxHours: Double) -> AgendaItem? {
        items
            .filter { item in
                guard case .event = item.kind, !item.isAllDay,
                      let start = item.start, let end = item.end else { return false }
                guard start <= now, end > now else { return false }
                guard calendar.isDate(start, inSameDayAs: now) else { return false }
                return end.timeIntervalSince(start) <= maxHours * 3600
            }
            .min { ($0.end ?? .distantFuture) < ($1.end ?? .distantFuture) }
    }

    /// Lädt beim App-Start — aber nur, wenn die Berechtigung schon erteilt ist.
    ///
    /// Ohne das zeigte die Menüleiste nach jedem Start **nur das Datum**:
    /// `reload()` steigt aus, solange `loadedRange` nil ist, und gesetzt wurde
    /// das bis 2026-09-22 ausschließlich von `PopoverView`. Der Minuten-Timer
    /// rief also brav `refreshNextEvent()` — über ein leeres `items`. Erfolg
    /// gemeldet, während eine Vorbedingung verletzt war. Erst ein Klick auf das
    /// Symbol füllte die Leiste (Befund von Michael, 2026-09-22).
    ///
    /// Bewusst nur **Lesen** des Status, nie `requestAccess()`: Der Vorsatz,
    /// beim Login keinen Berechtigungsdialog aufzuwerfen, bleibt unangetastet.
    /// Beim allerersten Start ist der Status `.notDetermined` — dann tut diese
    /// Funktion nichts und das Popover fragt wie bisher beim ersten Öffnen.
    func loadIfAlreadyAuthorized() async {
        // BEDINGUNGSLOS protokollieren, als Erstes. Dieser Messpunkt darf nicht
        // davon abhaengen, dass jemand das Popover oeffnet oder einen Knopf
        // drueckt — genau daran ist die Diagnose am 2026-09-22 dreimal
        // gescheitert: Der Messpunkt sass im Anfrage-Pfad, und der lief nie.
        //
        // Die Rohwerte stehen mit dabei, weil die uebersetzten Bezeichnungen
        // eine Interpretation sind. 0 = notDetermined, 1 = restricted,
        // 2 = denied, 3 = fullAccess, 4 = writeOnly.
        Self.log.notice("START — Kalender \(self.eventPermission.label, privacy: .public), Erinnerungen \(self.reminderPermission.label, privacy: .public), canPrompt \(self.canPrompt, privacy: .public), Rohwerte event=\(EKEventStore.authorizationStatus(for: .event).rawValue, privacy: .public) reminder=\(EKEventStore.authorizationStatus(for: .reminder).rawValue, privacy: .public)")

        let e = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        let r = EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
        guard e || r else { return }

        access = switch (e, r) {
        case (true, true): .granted
        default: .partial(events: e, reminders: r)
        }

        loadSources()
        await load(month: Date(), calendar: .current)
    }

    /// Von außen aufrufbar, damit der Menüleisten-Text mitwandert, ohne alles neu zu laden.
    func refreshNextEvent() { recomputeNextEvent() }
}
