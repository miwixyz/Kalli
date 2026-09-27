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
    nonisolated static let prefix = "kalli.termin."

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

        /// Klick auf die Update-Erinnerung (siehe `Updater`). Es gibt nur einen
        /// Delegate pro App — deshalb landet auch dieser Klick hier.
        func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            didReceive response: UNNotificationResponse
        ) async {
            guard response.notification.request.identifier == Updater.erinnerungsID else { return }
            await MainActor.run {
                NotificationCenter.default.post(name: .kalliUpdateErinnerungGeklickt, object: nil)
            }
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
    /// Aufgerufen über `CalendarStore.refreshBar()` — bei jedem `reload()`
    /// (EventKit-Änderungen, Popover-Navigation, Aufwachen, Tageswechsel) und
    /// stündlich aus dem Minutentimer der Leiste. (Bis 2026-09-27 stand hier „minütlich";
    /// das stimmte nie — Audit-Fund K-C4.) Weil es jederzeit laufen kann, ist
    /// die Regel wichtig, **nie** eine bereits fällige Mitteilung abzuräumen:
    /// Ein Entfernen um 09:59:59 und ein Neuplanen mit einem Auslöser in der
    /// Vergangenheit hieße, dass sie nie erscheint. Entfernt wird
    /// ausschließlich, was zu keinem meldeberechtigten Termin mehr gehört.
    /// `horizon` muss die Termine der **nächsten 24 Stunden** sein, eigens
    /// abgefragt — nicht die Liste, die die Oberfläche gerade anzeigt.
    ///
    /// Der Unterschied war der schwerste Fund des Audits vom 2026-09-22: Mit der
    /// Oberflächen-Liste genügte ein Klick auf „nächster Monat", damit die
    /// heutigen Termine fehlten, als gelöscht galten und ihre bereits geplanten
    /// Mitteilungen entfernt wurden. Das Feature schaltete sich still ab.
    ///
    /// Gibt zurück, ob geplant werden **durfte**. `false` heißt: eingeschaltet,
    /// aber macOS erlaubt keine Mitteilungen (Audit-Fund K-C11) — bis
    /// 2026-09-27 wurde das nur beim Einschalten geprüft, danach still ins
    /// Leere geplant.
    @discardableResult
    func sync(horizon: [AgendaItem], enabled: Bool, leadMinutes: Int) async -> Bool {
        guard enabled else {
            await removeAll()
            return true
        }

        guard await isAuthorized() else {
            // Kein Termininhalt im Protokoll — nur der Zustand.
            Self.log.notice("Mitteilungen eingeschaltet, aber von macOS nicht erlaubt — nichts geplant")
            return false
        }

        let now = Date()
        let lead = TimeInterval(leadMinutes * 60)

        let candidates = Self.candidates(in: horizon, now: now, lead: lead)

        let pending = await center.pendingNotificationRequests()
        let stale = Self.staleIdentifiers(pending: pending.map(\.identifier), horizon: horizon)
        if !stale.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: stale)
            Self.log.notice("\(stale.count, privacy: .public) gegenstandslose Mitteilung(en) abgeräumt")
        }

        for item in candidates {
            guard let start = item.start else { continue }
            await schedule(item: item, fireAt: start.addingTimeInterval(-lead), leadMinutes: leadMinutes)
        }

        Self.log.notice("Geplant: \(candidates.count, privacy: .public) Mitteilung(en), Vorlauf \(leadMinutes, privacy: .public) Min., Horizont \(horizon.count, privacy: .public) Termin(e)")
        return true
    }

    /// Darf dieser Termin überhaupt eine Mitteilung bekommen — unabhängig vom
    /// Zeitpunkt? Gemeinsame Grundlage für Planen und Aufräumen.
    nonisolated static func isEligible(_ item: AgendaItem) -> Bool {
        guard case .event = item.kind, !item.isAllDay, !item.hasAlarms,
              item.start != nil else { return false }
        return true
    }

    /// Welche geplanten Kalli-Mitteilungen gegenstandslos sind.
    ///
    /// „Bekannt" ist nur, was **meldeberechtigt** ist — nicht alles im
    /// Horizont. Bis 2026-09-27 zählte der ganze Horizont (Audit-Fund K-C3):
    /// Bekam ein Termin nachträglich einen eigenen Kalender-Alarm oder wurde er
    /// ganztägig, blieb Kallis Mitteilung stehen — es klingelte doch zweimal.
    ///
    /// Bewusst **nicht** gegen `candidates` geprüft: Ein berechtigter Termin,
    /// dessen Vorlauf gerade begonnen hat, ist kein Kandidat mehr, seine
    /// Mitteilung aber womöglich fällig. Die bleibt stehen.
    /// Sichtbarkeit des Kalenders steckt im Horizont selbst: ausgeblendete
    /// Kalender fragt `fetchEvents` gar nicht erst ab.
    nonisolated static func staleIdentifiers(pending: [String], horizon: [AgendaItem]) -> [String] {
        let known = Set(horizon.filter(isEligible).map { prefix + $0.id })
        return pending.filter { $0.hasPrefix(prefix) && !known.contains($0) }
    }

    /// Welche Termine eine Mitteilung bekommen.
    ///
    /// Reine Funktion mit übergebenem `now`, damit die Regel ohne Uhr und ohne
    /// Mitteilungszentrale prüfbar ist. Drei Ausschlüsse, jeder mit Grund:
    ///   - **ganztägig** — „beginnt in 10 Minuten" ist dort bedeutungslos
    ///   - **eigener Kalender-Alarm** — sonst klingelt es zweimal für denselben
    ///     Termin, und dann glaubt man keinem von beiden
    ///   - **Hinweiszeitpunkt liegt in der Vergangenheit** — eine Mitteilung mit
    ///     Auslöser in der Vergangenheit erscheint nie
    nonisolated static func candidates(in horizon: [AgendaItem], now: Date,
                                       lead: TimeInterval) -> [AgendaItem] {
        horizon.filter { item in
            guard isEligible(item), let start = item.start else { return false }
            return start.addingTimeInterval(-lead) > now
        }
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
            // Titel `.private`: Termininhalte gehören nicht lesbar ins
            // Systemprotokoll (Audit-Fund K-S1). Der Fehlertext reicht zur Diagnose.
            Self.log.error("""
                Planen fehlgeschlagen für \(item.title, privacy: .private): \
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
