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
/// (Nachgezogen 0.5.0: URL, Ort, Notizen und Teilnahmestatus werden gelesen.)
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
    nonisolated static let maxRunningHours: Double = 12

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
    private let fullScreenAlerts = FullScreenAlerts()
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
        // Aufwachen und Tageswechsel: Nach dem Ruhezustand ist das Leisten-
        // Fenster veraltet und die Mitteilungs-Planung womöglich auch — bis
        // 2026-09-27 wurde nur bei `reload()` neu geplant, und das lief allein
        // bei EventKit-Änderungen oder Popover-Navigation (Audit-Fund K-C4).
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.reload() }
        }
        dayObserver = NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.reload() }
        }
        #if DEBUG
        Task { @MainActor [weak self] in self?.fullScreenAlerts.showDemoIfRequested() }
        #endif
    }

    private var wakeObserver: NSObjectProtocol?
    private var dayObserver: NSObjectProtocol?

    // Kein deinit — gleiche Begründung wie in MenuBarLabel: nonisolated deinit
    // kommt an MainActor-Eigenschaften nicht heran, und die Instanz lebt so
    // lange wie die App. Der Block hält `self` schwach.
    func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
        if let dayObserver { NotificationCenter.default.removeObserver(dayObserver) }
        observer = nil
        wakeObserver = nil
        dayObserver = nil
    }

    // MARK: - Berechtigung

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

    /// Liest den Berechtigungsstand frisch von macOS und lädt, wenn er sich
    /// geändert hat. Aufgerufen bei jedem Öffnen des Popovers.
    ///
    /// Audit-Fund K-C7 (2026-09-27): `access` wurde nur beim Start und bei
    /// einer Anfrage gesetzt. Wer den Zugriff danach in den Systemeinstellungen
    /// erteilte, sah bis zum Neustart weiter „Kein Zugriff auf Kalender".
    func refreshAccess() async {
        let e = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        let r = EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
        let fresh = Self.access(events: e, reminders: r)
        guard fresh != access else { return }
        Self.log.notice("Berechtigung hat sich geaendert — Kalender \(e, privacy: .public), Erinnerungen \(r, privacy: .public)")
        let (hadEvents, hadReminders): (Bool, Bool) = switch access {
        case .granted: (true, true)
        case .partial(let events, let reminders): (events, reminders)
        case .denied, .unknown: (false, false)
        }
        access = fresh
        guard e || r else {
            // Beides entzogen: Nichts Altes stehen lassen — die Leiste zeigte
            // sonst Termine, die Kalli nicht mehr lesen darf (Review-Fund).
            // loadSources() hier NICHT: siehe hiddenAfterPrune.
            items = []
            barItems = []
            nextEvent = nil
            runningEvent = nil
            return
        }
        // Apple, `requestAccess(to:completion:)`: Hat die App vor der Freigabe
        // schon zugegriffen, „it may be necessary to reset the event store to
        // ensure data becomes accessible". Kalli hält keine EventKit-Objekte
        // über diesen Punkt hinaus (nur `AgendaItem`-Werte), also gefahrlos.
        // Ob es ohne reset() hier auch ginge, ist nicht gemessen.
        if (e && !hadEvents) || (r && !hadReminders) { store.reset() }
        loadSources()
        await reload()
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
        prefs.pruneHidden(to: Self.hiddenAfterPrune(
            prefs.hiddenSourceIDs, found: Set(found.map(\.id)),
            eventsReadable: EKEventStore.authorizationStatus(for: .event) == .fullAccess,
            remindersReadable: EKEventStore.authorizationStatus(for: .reminder) == .fullAccess))
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

    /// Lädt genau die Tage, die das Raster zeigt — dieselbe Funktion wie
    /// `MonthGrid` (`MonthRaster`), damit beide nicht auseinanderlaufen.
    func load(month: Date, calendar: Calendar) async {
        guard let range = MonthRaster.interval(for: month, calendar: calendar) else { return }
        loadedRange = range
        await reload()
    }

    func reload() async {
        guard let range = loadedRange else { return }
        var collected = await fetchEvents(in: range)
        collected += await fetchReminders(in: range)
        // Überlappende Läufe (Review-Fund): Hat während des Wartens ein
        // Monatswechsel den Zeitraum geändert, gehört dieses Ergebnis zum
        // alten Monat — verwerfen, der neuere Lauf übernimmt alles Weitere.
        // Bewusst kein Generationszähler: Der ließe auch den Lauf aus
        // `setCompleted` verfallen, dessen Nachprüfung genau diese Liste braucht.
        guard range == loadedRange else { return }
        items = collected.sorted { lhs, rhs in
            (lhs.start ?? .distantFuture) < (rhs.start ?? .distantFuture)
        }
        await refreshBar()
    }

    /// Nur Leiste und Mitteilungen neu — ohne den Popover-Monat. Für den
    /// stündlichen Tick: zwei Abfragen statt vier.
    func refreshBar() async {
        // Wie reload(): Vor dem ersten Laden (keine Berechtigung) nichts tun —
        // sonst räumte syncAlerts mit leerem Horizont alle Mitteilungen ab.
        guard loadedRange != nil else { return }
        barItems = await fetchEvents(in: Self.barWindow(now: Date()))
        recomputeNextEvent()
        syncFullScreenAlerts()
        await syncAlerts()
    }

    /// Plant die Vollbild-Hinweise neu. Quelle ist `barItems` (jetzt −12 h … +24 h,
    /// stündlich und bei jeder EventKit-Änderung frisch abgefragt), nicht `items`:
    /// gleiche Lehre wie beim Mitteilungs-Horizont, `items` ist nur eine Ansicht.
    func syncFullScreenAlerts() {
        fullScreenAlerts.sync(horizon: barItems,
                              enabled: prefs.fullScreenBeforeEvent,
                              leadMinutes: prefs.fullScreenLeadMinutes)
    }

    /// Termine rund um **jetzt** — die Quelle für Leiste, Puls und Popover-Hinweis.
    ///
    /// Audit-Fund K-C5 (2026-09-27): `nextEvent`/`runningEvent` wurden aus
    /// `items` berechnet, also aus dem Monat, den das Popover gerade zeigt.
    /// Einmal „nächster Monat" geklickt und geschlossen — Leiste leer. Und ohne
    /// Popover blieb der beim Start geladene Monat stehen: Eine Instanz vom
    /// 24.09. hätte ab dem 08.10. nichts mehr angezeigt. Gleiche Lehre wie beim
    /// Mitteilungs-Horizont: `items` ist eine Ansicht, keine Quelle.
    private var barItems: [AgendaItem] = []

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
            notificationsBlocked = false
            return
        }
        // Bewusst NICHT `items`: siehe fetchAlertHorizon().
        let planned = await alerts.sync(
            horizon: await fetchAlertHorizon(),
            enabled: true,
            leadMinutes: prefs.alertLeadMinutes
        )
        notificationsBlocked = !planned
    }

    /// Schalter „Systemmitteilung" ist an, aber macOS erlaubt keine
    /// Mitteilungen (später entzogen). Die Einstellungen zeigen dann einen
    /// Hinweis, statt einen Schalter, der „an" zeigt und nichts tut (K-C11).
    private(set) var notificationsBlocked = false

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
            hasAlarms: ev.hasAlarms,
            link: MeetingLink.find(url: ev.url, location: ev.location, notes: ev.notes),
            isDeclined: ev.attendees?.first(where: \.isCurrentUser)?.participantStatus == .declined
        )
    }

    nonisolated private static func eventID(_ ev: EKEvent) -> String {
        eventID(base: ev.eventIdentifier, start: ev.startDate)
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
    nonisolated static let alertHorizon: TimeInterval = 24 * 3600

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
                hasAlarms: rem.hasAlarms,
                isRecurring: rem.hasRecurrenceRules
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
        // VOR dem Speichern festhalten: Beim Abhaken einer Serie verändert
        // EventKit womöglich dasselbe Objekt (siehe completionConfirmed).
        let recurring = reminder.hasRecurrenceRules
        let dueBefore = reminder.dueDateComponents?.date
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
        let fresh: (isCompleted: Bool, due: Date?)?
        if let row = items.first(where: { $0.id == item.id }) {
            fresh = (row.isCompleted, row.start)
        } else if recurring, let again = store.calendarItem(withIdentifier: item.id) as? EKReminder {
            // Die weitergeschobene Fälligkeit liegt womöglich außerhalb des
            // geladenen Zeitraums — dann direkt nachlesen.
            fresh = (again.isCompleted, again.dueDateComponents?.date)
        } else {
            fresh = nil
        }
        guard let fresh else {
            // Kein Beweis moeglich: Die Erinnerung liegt ausserhalb des
            // geladenen Zeitraums. Das ist kein Fehler, aber auch keine
            // Bestaetigung — und wird als das protokolliert, was es ist.
            Self.log.notice("Nicht nachpruefbar — Erinnerung liegt ausserhalb des geladenen Zeitraums. Liste \(listName, privacy: .public), Ziel \(completed, privacy: .public).")
            return nil
        }

        if !Self.completionConfirmed(target: completed, isCompleted: fresh.isCompleted,
                                     recurring: recurring, dueBefore: dueBefore, dueAfter: fresh.due) {
            Self.log.error("Haekchen NICHT angekommen — Liste \(listName, privacy: .public): gesetzt auf \(completed, privacy: .public), zurueckgelesen \(fresh.isCompleted, privacy: .public), wiederkehrend \(recurring, privacy: .public).")
            return completed
                ? "Das Häkchen ist nicht angekommen — Apple Erinnerungen hat es nicht übernommen."
                : "Das Zurücknehmen ist nicht angekommen — Apple Erinnerungen hat es nicht übernommen."
        }

        Self.log.notice("Haekchen bestaetigt — Liste \(listName, privacy: .public), jetzt \(fresh.isCompleted, privacy: .public), wiederkehrend \(recurring, privacy: .public).")
        return nil
    }

    // MARK: - Abfragen

    func items(on day: Date, calendar: Calendar) -> [AgendaItem] {
        items.filter { Self.occurs($0, on: day, calendar: calendar) }
    }

    func hasItems(on day: Date, calendar: Calendar) -> Bool {
        !items(on: day, calendar: calendar).isEmpty
    }

    private func recomputeNextEvent(now: Date = Date()) {
        // `barItems`, nicht `items` — siehe dort (K-C5).
        (nextEvent, runningEvent) = Self.barState(from: barItems, now: now)
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
    func refreshNextEvent(now: Date = Date()) { recomputeNextEvent(now: now) }

    #if DEBUG
    /// Nur für Tests: beide Listen setzen, ohne EventKit. Damit prüfbar ist,
    /// dass die Leiste aus `barItems` rechnet und nicht aus `items`.
    func setListsForTesting(items: [AgendaItem], barItems: [AgendaItem]) {
        self.items = items
        self.barItems = barItems
    }
    #endif
}
