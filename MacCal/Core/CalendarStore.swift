import EventKit
import Foundation
import Observation

/// Liest Termine und Erinnerungen. Ausschließlich lesend — MacCal schreibt nie
/// in EventKit zurück.
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

    private let store = EKEventStore()
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

    func requestAccess() async {
        async let eventsOK = requestEvents()
        async let remindersOK = requestReminders()
        let (e, r) = await (eventsOK, remindersOK)

        access = switch (e, r) {
        case (true, true): .granted
        case (false, false): .denied
        default: .partial(events: e, reminders: r)
        }

        if e || r {
            loadSources()
            await reload()
        }
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
    }

    private func fetchEvents(in range: DateInterval) async -> [AgendaItem] {
        let cals = store.calendars(for: .event).filter { !prefs.isHidden($0.calendarIdentifier) }
        guard !cals.isEmpty else { return [] }

        let predicate = store.predicateForEvents(
            withStart: range.start, end: range.end, calendars: cals
        )
        // Wiederkehrende Termine werden hier NICHT selbst aufgelöst. EventKit
        // expandiert sie inklusive Ausnahmen und verschobener Einzeltermine.
        // Wer das selbst rechnet, baut sich Fehler für Monate ein.
        return store.events(matching: predicate).map { ev in
            AgendaItem(
                id: ev.eventIdentifier ?? UUID().uuidString,
                title: ev.title ?? "(ohne Titel)",
                start: ev.startDate,
                end: ev.endDate,
                isAllDay: ev.isAllDay,
                hasTime: !ev.isAllDay,
                kind: .event,
                sourceID: ev.calendar?.calendarIdentifier ?? "",
                color: ev.calendar.map(Self.rgba) ?? .fallback
            )
        }
    }

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
                color: rem.calendar.map(rgba) ?? .fallback
            )
        }
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
        nextEvent = items.first { item in
            guard case .event = item.kind, !item.isAllDay, let start = item.start else { return false }
            return start > now
        }
        // Ganztägige laufen per Definition den ganzen Tag — ein Fortschritt
        // daran wäre die Uhrzeit, keine Information über den Termin.
        //
        // Zwei weitere Einschränkungen, beide aus dem Befund vom 2026-09-21,
        // dass ein Termin von *gestern* als laufend angezeigt wurde:
        //   1. Der Termin muss heute begonnen haben. `start <= now && end > now`
        //      ist formal richtig, trifft aber auch mehrtägige Termine, deren
        //      Ende zufällig in der Zukunft liegt. Ein Fortschrittsbalken über
        //      zwei Tage sagt nichts.
        //   2. Termine über MAX_RUNNING_HOURS sind eher Zustände als Termine
        //      (Urlaub, Bereitschaft) — ein Prozentwert darauf ist Rauschen.
        let calendar = Calendar.current
        runningEvent = items.first { item in
            guard case .event = item.kind, !item.isAllDay,
                  let start = item.start, let end = item.end else { return false }
            guard start <= now, end > now else { return false }
            guard calendar.isDateInToday(start) else { return false }
            return end.timeIntervalSince(start) <= Self.maxRunningHours * 3600
        }
    }

    /// Von außen aufrufbar, damit der Menüleisten-Text mitwandert, ohne alles neu zu laden.
    func refreshNextEvent() { recomputeNextEvent() }
}
