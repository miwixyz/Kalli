import Foundation
import OSLog
import UserNotifications

/// Systemmitteilungen für bevorstehende Termine.
///
/// **Bewusst nur für Termine ohne eigenen Alarm.** Trägt der Termin im Kalender
/// schon eine Erinnerung, meldet Apple Kalender selbst — Kalli hält dann still.
/// Zwei Klingeln für denselben Termin sind kein doppelter Hinweis, sondern
/// einer, dem man nicht mehr glaubt. (Entschieden mit Michael, 2026-09-22.)
///
/// **Die Berechtigung wird erst beim Einschalten erfragt**, nicht beim Start —
/// gleiche Haltung wie beim Kalenderzugriff: Ein Dialog, der ungefragt beim
/// Login aufpoppt, wird reflexhaft weggeklickt, und dann ist die Funktion still
/// kaputt.
@MainActor
final class EventAlerts {

    /// Messpunkt. Von aussen lesbar mit:
    ///
    ///     log show --last 30m --predicate 'subsystem == "com.kalli.app"'
    ///
    /// Auf Stufe `notice`, nicht `info`: `info` haelt macOS nur im Speicher.
    /// Ein Messpunkt, der nicht auf der Platte landet, ist am naechsten Tag
    /// keiner mehr — genau das ist am 2026-09-22 passiert.
    private static let log = Logger(subsystem: "com.kalli.app", category: "mitteilungen")

    /// Alles, was Kalli plant, traegt dieses Praefix. Damit lassen sich eigene
    /// Mitteilungen von fremden unterscheiden, ohne eine Liste zu fuehren.
    private static let prefix = "kalli.termin."

    /// Wie weit im Voraus geplant wird. Weiter zu planen bringt nichts: Die App
    /// laeuft dauerhaft und rechnet minuetlich nach.
    private static let horizon: TimeInterval = 24 * 3600

    private let center = UNUserNotificationCenter.current()
    private let presenter = Presenter()

    init() {
        center.delegate = presenter
    }

    /// Damit Mitteilungen auch erscheinen, wenn Kalli gerade die vordergründige
    /// App ist — also wenn das Popover offen steht.
    ///
    /// Ohne Delegate unterdrückt macOS sie in diesem Fall stillschweigend. Man
    /// hätte den Hinweis dann genau in dem Moment nicht bekommen, in dem man in
    /// den Kalender schaut. Ein Kanal, der unter einer Bedingung schweigt, die
    /// niemand kennt, ist schlimmer als keiner.
    private final class Presenter: NSObject, UNUserNotificationCenterDelegate {
        func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            willPresent notification: UNNotification
        ) async -> UNNotificationPresentationOptions {
            [.banner, .sound]
        }
    }

    /// Fragt die Berechtigung an. Gibt zurueck, ob sie danach vorliegt.
    ///
    /// Der Rueckgabewert ist **gemessen, nicht angenommen**: Nach dem Request
    /// wird der Status neu gelesen. `requestAuthorization` liefert `true` auch
    /// dann, wenn der Nutzer nur „einmal erlauben" gewaehlt hat oder eine
    /// Profilverwaltung mitredet.
    func requestPermission() async -> Bool {
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            Self.log.error("Berechtigung fehlgeschlagen: \(error.localizedDescription, privacy: .public)")
            return false
        }
        let granted = await isAuthorized()
        Self.log.notice("Berechtigung nach Anfrage: \(granted, privacy: .public)")
        return granted
    }

    func isAuthorized() async -> Bool {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
    }

    /// Bringt die geplanten Mitteilungen auf den Stand der übergebenen Termine.
    ///
    /// Idempotent: Mehrfaches Aufrufen mit denselben Terminen ändert nichts.
    /// Wird minütlich aufgerufen — deshalb ist die Regel wichtig, **nie** eine
    /// bereits fällige Mitteilung abzuräumen: Ein Entfernen um 09:59:59 und ein
    /// Neuplanen mit einem Auslöser in der Vergangenheit hieße, dass sie nie
    /// erscheint. Entfernt wird ausschließlich, was zu einem Termin gehört, den
    /// es nicht mehr gibt.
    func sync(items: [AgendaItem], enabled: Bool, leadMinutes: Int) async {
        guard enabled else {
            await removeAll()
            return
        }

        let now = Date()
        let lead = TimeInterval(leadMinutes * 60)

        // Kandidaten: echte Termine, nicht ganztaegig, ohne eigenen Alarm,
        // deren Hinweiszeitpunkt noch in der Zukunft liegt.
        let candidates = items.filter { item in
            guard case .event = item.kind, !item.isAllDay, !item.hasAlarms,
                  let start = item.start else { return false }
            let fire = start.addingTimeInterval(-lead)
            return fire > now && start.timeIntervalSince(now) < Self.horizon
        }

        let wanted = Set(candidates.map { Self.prefix + $0.id })

        // Aufräumen: nur Mitteilungen zu Terminen, die es nicht mehr gibt.
        // Alles andere wird gleich ohnehin mit gleicher Kennung ersetzt.
        let known = Set(items.map { Self.prefix + $0.id })
        let pending = await center.pendingNotificationRequests()
        let stale = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.prefix) && !known.contains($0) }
        if !stale.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: stale)
            Self.log.notice("\(stale.count, privacy: .public) Mitteilung(en) zu entfernten Terminen abgeräumt")
        }

        for item in candidates {
            guard let start = item.start else { continue }
            await schedule(item: item, fireAt: start.addingTimeInterval(-lead), leadMinutes: leadMinutes)
        }

        Self.log.notice("""
            Geplant: \(wanted.count, privacy: .public) Mitteilung(en), \
            Vorlauf \(leadMinutes, privacy: .public) Min.
            """)
    }

    private func schedule(item: AgendaItem, fireAt: Date, leadMinutes: Int) async {
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.sound = .default

        // Handlungsanweisung statt bloßer Meldung: Die Mitteilung sagt, wann es
        // losgeht und wie lange es dauert — damit man entscheiden kann, ohne
        // erst den Kalender zu öffnen.
        let time = Self.timeFormatter.string(from: item.start ?? fireAt)
        if let end = item.end, end > (item.start ?? fireAt) {
            let endTime = Self.timeFormatter.string(from: end)
            content.body = "Beginnt in \(leadMinutes) Min. · \(time)–\(endTime)"
        } else {
            content.body = "Beginnt in \(leadMinutes) Min. · \(time)"
        }

        // Absolute Auslösezeit über Datumsbestandteile. Ein
        // `UNTimeIntervalNotificationTrigger` würde bei jedem Neuplanen relativ
        // zu *jetzt* rechnen und dadurch minütlich leicht wandern.
        let comps = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute], from: fireAt
        )
        let request = UNNotificationRequest(
            identifier: Self.prefix + item.id,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        )

        do {
            try await center.add(request)
        } catch {
            // Nicht schlucken. Eine Mitteilung, die stumm nicht geplant wurde,
            // ist schlimmer als keine — man verlässt sich darauf.
            Self.log.error("""
                Planen fehlgeschlagen für \(item.title, privacy: .public): \
                \(error.localizedDescription, privacy: .public)
                """)
        }
    }

    func removeAll() async {
        let pending = await center.pendingNotificationRequests()
        let mine = pending.map(\.identifier).filter { $0.hasPrefix(Self.prefix) }
        guard !mine.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: mine)
        Self.log.notice("\(mine.count, privacy: .public) Mitteilung(en) entfernt (abgeschaltet)")
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "HH:mm"
        return f
    }()
}
