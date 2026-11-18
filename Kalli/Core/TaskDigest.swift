import Foundation
import Observation
import OSLog

/// Tägliches Pop-up mit den heute fälligen Aufgaben (0.15.0, Michael 2026-11-17).
///
/// Einmal am Tag zur eingestellten Uhrzeit erscheint ein kleines Glasfenster mit den offenen
/// Erinnerungen, die heute fällig sind. „In 1 Std. wieder" holt es eine Stunde später zurück,
/// „Schließen" beendet es für heute. Sind zur Uhrzeit (oder nach dem Schlummern) keine offenen
/// Aufgaben da, erscheint nichts.
///
/// **Entscheidungen:**
/// - Nur **heute** fällige, offene Erinnerungen aus eingeblendeten Listen. Überfällige vom
///   Vortag gehören nicht dazu (die Tagesliste ordnet sie ebenfalls ihrem Tag zu).
/// - Kein Vollbild und kein Tastaturfokus: Das Fenster liegt oben links über der Arbeit (oben
///   rechts stehen die Mitteilungen von macOS; Michael, 2026-11-18) und nimmt keine Eingaben weg. Es bleibt stehen, bis man es schließt oder schlummert.
/// - War der Mac zur Uhrzeit aus oder im Ruhezustand, kommt das Pop-up beim nächsten Aufwachen
///   am selben Tag nach.
/// - „Für heute erledigt" und der Schlummer-Zeitpunkt stehen in den UserDefaults, damit ein
///   Neustart der App das Pop-up nicht ein zweites Mal bringt bzw. das Schlummern nicht vergisst.
@MainActor
final class TaskDigest {

    /// Messpunkt: `log show --last 30m --predicate 'subsystem == "com.kalli.app" AND category == "aufgaben"'`
    private static let log = Logger(subsystem: "com.kalli.app", category: "aufgaben")

    nonisolated static let snoozeInterval: TimeInterval = 3600

    private enum Key {
        static let handledDay = "taskDigestHandledDay"
        static let snoozeUntil = "taskDigestSnoozeUntil"
    }

    private let prefs: Preferences
    private let store: CalendarStore
    private let defaults: UserDefaults
    private let calendar = Calendar.current
    private let presenter = TaskDigestPresenter()
    private var timer: Timer?
    /// Eine Abfrage läuft gerade — `sync` kommt bei jeder Kalenderänderung und darf keine zweite starten.
    private var checking = false

    init(prefs: Preferences, store: CalendarStore, defaults: UserDefaults = .standard) {
        self.prefs = prefs
        self.store = store
        self.defaults = defaults
    }

    func start() {
        sync()
        observe()
    }

    /// `store.revision` ändert sich bei EventKit-Änderungen, Aufwachen, Tageswechsel und stündlich.
    private func observe() {
        withObservationTracking {
            _ = prefs.taskDigestEnabled
            _ = prefs.taskDigestHour
            _ = store.revision
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.sync()
                self?.observe()
            }
        }
    }

    /// Idempotent: stellt den Timer neu oder zeigt sofort, wenn der Zeitpunkt erreicht ist.
    private func sync(now: Date = Date()) {
        timer?.invalidate()
        timer = nil
        guard prefs.taskDigestEnabled else {
            presenter.close()
            return
        }
        guard !presenter.isOpen else { return }
        guard let at = Self.nextFire(now: now, hour: prefs.taskDigestHour, handledDay: handledDay,
                                     snoozeUntil: snoozeUntil, calendar: calendar) else { return }
        if at <= now {
            Task { await fire() }
        } else {
            let t = Timer(fire: at, interval: 0, repeats: false) { [weak self] _ in
                Task { @MainActor [weak self] in self?.sync() }
            }
            t.tolerance = 5
            RunLoop.main.add(t, forMode: .common)
            timer = t
        }
    }

    private func fire() async {
        guard !checking, !presenter.isOpen else { return }
        checking = true
        defer { checking = false }
        // Ohne Zugriff liefert die Abfrage eine leere Liste. Die darf den Tag nicht als erledigt
        // markieren — sonst bliebe das Pop-up nach erteilter Freigabe für heute aus.
        guard store.reminderPermission == .granted else {
            Self.log.error("Aufgaben-Pop-up fällig, aber kein Zugriff auf Erinnerungen — nichts gezeigt")
            return
        }
        let now = Date()
        let tasks = await openTasksToday()
        snoozeUntil = nil
        guard !tasks.isEmpty else {
            handledDay = now
            Self.log.notice("Aufgaben-Pop-up: keine offenen Aufgaben für heute — nichts gezeigt")
            sync()
            return
        }
        presenter.show(TaskDigestView(
            items: tasks,
            load: { [weak self] in await self?.openTasksToday() ?? [] },
            toggle: { [weak self] item in await self?.store.setCompleted(true, for: item) },
            onSnooze: { [weak self] in self?.snooze() },
            onClose: { [weak self] in self?.finish() },
            onResize: { [weak self] in self?.presenter.refit() }
        ), prefs: prefs, store: store)
        Self.log.notice("Aufgaben-Pop-up gezeigt: \(tasks.count, privacy: .public) Aufgabe(n)")
    }

    private func openTasksToday() async -> [AgendaItem] {
        Self.openTasks(in: await store.dayItems(Date(), calendar: calendar))
    }

    private func snooze() {
        presenter.close()
        let now = Date()
        if let until = Self.snoozeDate(now: now, calendar: calendar) {
            snoozeUntil = until
            Self.log.notice("Aufgaben-Pop-up geschlummert bis \(until, privacy: .public)")
        } else {
            handledDay = now
        }
        sync()
    }

    /// „Schließen" oder alles abgehakt: für heute fertig.
    private func finish() {
        presenter.close()
        snoozeUntil = nil
        handledDay = Date()
        Self.log.notice("Aufgaben-Pop-up für heute geschlossen")
        sync()
    }

    private var handledDay: Date? {
        get { defaults.object(forKey: Key.handledDay) as? Date }
        set { defaults.set(newValue, forKey: Key.handledDay) }
    }

    private var snoozeUntil: Date? {
        get { defaults.object(forKey: Key.snoozeUntil) as? Date }
        set { defaults.set(newValue, forKey: Key.snoozeUntil) }
    }

    #if DEBUG
    /// Nur in Debug-Builds: `open Kalli.app --args -aufgabenDemo` zeigt das Pop-up sofort mit
    /// Beispielaufgaben. Abhaken entfernt sie nur aus dem Fenster, geschrieben wird nichts.
    func showDemoIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-aufgabenDemo") else { return }
        presenter.show(Self.demoView(onClose: { [weak self] in self?.presenter.close() },
                                     onResize: { [weak self] in self?.presenter.refit() }),
                       prefs: prefs, store: store)
    }

    static func demoView(onClose: @escaping () -> Void = {}, onResize: @escaping () -> Void = {}) -> TaskDigestView {
        let noon = Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: Date()) ?? Date()
        func task(_ n: Int, _ title: String, at offset: TimeInterval? = nil, urgent: Bool = false) -> AgendaItem {
            AgendaItem(id: "demo.\(n)", title: title, start: noon.addingTimeInterval(offset ?? 0), end: nil,
                       isAllDay: false, hasTime: offset != nil, kind: .reminder(completed: false),
                       sourceID: "demo", color: RGBA(r: 0.24, g: 0.30, b: 0.60, a: 1), hasAlarms: false,
                       isUrgent: urgent)
        }
        let box = DemoBox(items: [
            task(1, "Angebot Kino Ottobrunn abschicken", at: -2 * 3600, urgent: true),
            task(2, "Rückruf Steuerberater", at: 3 * 3600),
            task(3, "Reel-Caption für Donnerstag schreiben"),
            task(4, "Rechnungen Oktober prüfen"),
        ])
        return TaskDigestView(items: box.items, load: { box.items },
                              toggle: { item in box.items.removeAll { $0.id == item.id }; return nil },
                              onSnooze: onClose, onClose: onClose, onResize: onResize)
    }

    @MainActor
    private final class DemoBox {
        var items: [AgendaItem]
        init(items: [AgendaItem]) { self.items = items }
    }
    #endif

    // MARK: - Regeln (rein, ohne Uhr testbar)

    /// Die Aufgaben für das Pop-up aus den Einträgen **eines** Tages: nur offene Erinnerungen.
    /// Reihenfolge: Dringende zuerst, dann mit Uhrzeit nach Fälligkeit, dann ohne Uhrzeit.
    nonisolated static func openTasks(in dayItems: [AgendaItem]) -> [AgendaItem] {
        func rank(_ item: AgendaItem) -> Int { item.isUrgent ? 0 : (item.hasTime ? 1 : 2) }
        return dayItems.filter { $0.isReminder && !$0.isCompleted }.sorted { lhs, rhs in
            if rank(lhs) != rank(rhs) { return rank(lhs) < rank(rhs) }
            let (ls, rs) = (lhs.start ?? .distantFuture, rhs.start ?? .distantFuture)
            if ls != rs { return ls < rs }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    /// Wann das Pop-up als Nächstes dran ist. Liegt der Zeitpunkt nicht in der Zukunft, ist es
    /// **jetzt** dran (Mac war zur Uhrzeit aus, App eben gestartet).
    ///
    /// - Läuft ein Schlummern von heute, gilt dessen Zeitpunkt. Ein Schlummern von einem früheren
    ///   Tag ist verfallen: Die Aufgaben von gestern sind nicht mehr „heute fällig".
    /// - Ist heute schon erledigt (`handledDay`), gilt die Uhrzeit von morgen.
    nonisolated static func nextFire(now: Date, hour: Int, handledDay: Date?, snoozeUntil: Date?,
                                     calendar: Calendar) -> Date? {
        let today = calendar.startOfDay(for: now)
        if let snoozeUntil, snoozeUntil >= today { return snoozeUntil }
        let handledToday = handledDay.map { calendar.isDate($0, inSameDayAs: now) } ?? false
        guard let day = handledToday ? calendar.date(byAdding: .day, value: 1, to: today) : today else { return nil }
        return calendar.date(bySettingHour: min(max(hour, 0), 23), minute: 0, second: 0, of: day)
    }

    /// Zeitpunkt für „In 1 Std. wieder". `nil`, wenn die Stunde über Mitternacht reichte — dann
    /// wären es nicht mehr die Aufgaben von heute, und das Schlummern wirkt wie Schließen.
    nonisolated static func snoozeDate(now: Date, calendar: Calendar) -> Date? {
        let until = now.addingTimeInterval(snoozeInterval)
        return calendar.isDate(until, inSameDayAs: now) ? until : nil
    }
}
