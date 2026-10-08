import Foundation
import OSLog

/// Vollbild-Hinweis kurz vor einem Termin — nach dem Vorbild von „In Your Face".
///
/// Die Systemmitteilung und der Puls in der Leiste lassen sich übersehen, wenn man
/// tief in einer Arbeit steckt. Dieser Hinweis legt sich über alle Bildschirme und
/// bleibt, bis man ihn schließt.
///
/// **Entscheidungen (mit Michael, 2026-09-29):**
/// - alle Termine mit Uhrzeit, auch die mit eigenem Kalender-Alarm (anderer Kanal
///   als die Mitteilung, keine Doppel-Klingel im selben Kanal)
/// - eigener Vorlauf (`fullScreenLeadMinutes`), ab Werk 1 Min.
/// - „Link öffnen" nur als einfacher Link-Knopf, keine Erkennung einzelner
///   Videokonferenz-Dienste (die stünde weiter unter „Draußen")
/// - nur Termine, keine Erinnerungen
/// - „Zum Beginn nochmal" (2026-10-08): bringt den Hinweis genau zum Terminbeginn zurück,
///   unabhängig vom eingestellten Vorlauf; ab 30 s vor Beginn ausgeblendet
///
/// **Präzise Timer statt Minutentakt:** Der Minutentimer der Leiste hat 10 s Toleranz
/// und keinen festen Sekundenbezug. Bei 1 Min. Vorlauf käme der Hinweis bis zu
/// einer Minute zu spät, also genau dann, wenn der Termin schon läuft.
@MainActor
final class FullScreenAlerts {

    /// Messpunkt: `log show --last 30m --predicate 'subsystem == "com.kalli.app"'`
    private static let log = Logger(subsystem: "com.kalli.app", category: "vollbild")

    /// Bis wie lange nach Beginn ein verpasster Hinweis noch nachgeholt wird, z. B.
    /// nach dem Aufwachen aus dem Ruhezustand. Später hilft er nicht mehr.
    nonisolated static let grace: TimeInterval = 5 * 60

    private var timers: [Timer] = []
    /// Bereits gezeigte Termine (Kennung je Vorkommen). Verhindert, dass derselbe
    /// Termin nach dem Schließen durch ein Neuplanen noch einmal erscheint.
    private var shown: Set<String> = []
    /// Termine, bei denen „Zum Beginn nochmal" gedrückt wurde. Sie erscheinen genau zum
    /// Beginn ein zweites Mal. Eigene Menge statt Timer allein, weil `sync` alle Timer
    /// neu stellt (stündlich, bei Kalenderänderungen) — ein reiner Timer ginge dabei verloren.
    private var snoozed: Set<String> = []
    private var horizon: [AgendaItem] = []
    private var lead: TimeInterval = 60
    private let presenter = FullScreenAlertPresenter()

    init() {
        presenter.onSnooze = { [weak self] items in self?.snooze(items, now: Date()) }
    }

    /// Idempotent. Läuft bei jedem `refreshBar()`: stündlich, bei EventKit-Änderungen,
    /// beim Umschalten in den Einstellungen.
    func sync(horizon: [AgendaItem], enabled: Bool, leadMinutes: Int,
              screens: FullScreenScreens = .all, now: Date = Date()) {
        presenter.screens = screens
        timers.forEach { $0.invalidate() }
        timers = []
        guard enabled else {
            self.horizon = []
            return
        }
        self.horizon = horizon
        lead = TimeInterval(max(0, leadMinutes) * 60)
        // Gezeigte Kennungen, die nicht mehr im Horizont stehen, vergessen.
        let ids = Set(horizon.map(\.id))
        shown.formIntersection(ids)
        snoozed.formIntersection(ids)

        // Liegt ein Hinweis schon im Fenster (App gerade gestartet, Termin eben
        // angelegt), sofort zeigen statt ihn still zu verlieren.
        fire(now: now)

        var fireDates = Set(Self.upcoming(in: horizon, now: now, lead: lead).compactMap { item in
            item.start.map { $0.addingTimeInterval(-lead) }
        })
        // Geschlummerte Termine: zum Beginn.
        fireDates.formUnion(horizon.compactMap { item in
            guard snoozed.contains(item.id), let start = item.start, start > now else { return nil }
            return start
        })
        fireDates.forEach(schedule)
        Self.log.notice("Vollbild: \(fireDates.count, privacy: .public) Zeitpunkt(e) geplant, Vorlauf \(Int(self.lead / 60), privacy: .public) Min., geschlummert \(self.snoozed.count, privacy: .public)")
    }

    private func schedule(_ date: Date) {
        let t = Timer(fire: date, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in self?.fire(now: Date()) }
        }
        t.tolerance = 1
        RunLoop.main.add(t, forMode: .common)
        timers.append(t)
    }

    /// Zeigt alles, was jetzt fällig und noch nicht gezeigt ist, in **einem** Hinweis —
    /// erste Hinweise und geschlummerte, die jetzt beginnen.
    private func fire(now: Date) {
        let first = Self.due(in: horizon, now: now, lead: lead, shown: shown)
        let again = Self.snoozeDue(in: horizon, now: now, snoozed: snoozed)
        guard !first.isEmpty || !again.isEmpty else { return }
        shown.formUnion(first.map(\.id))
        snoozed.subtract(again.map(\.id))
        Self.log.notice("Vollbild-Hinweis: \(first.count, privacy: .public) neu, \(again.count, privacy: .public) zum Beginn erneut")
        presenter.show(first + again)
    }

    /// „Zum Beginn nochmal": Termine, die noch nicht begonnen haben, kommen genau zum
    /// Beginn wieder. Bereits laufende werden nicht erneut gezeigt.
    private func snooze(_ items: [AgendaItem], now: Date) {
        let later = Self.snoozable(items, now: now)
        snoozed.formUnion(later.map(\.id))
        Set(later.compactMap(\.start)).forEach(schedule)
        Self.log.notice("Vollbild geschlummert: \(later.count, privacy: .public) von \(items.count, privacy: .public) Termin(en) kommen zum Beginn wieder")
    }

    #if DEBUG
    /// Nur in Debug-Builds: `open Kalli.app --args -vollbildDemo` zeigt den Hinweis
    /// sofort mit zwei Beispielterminen. Damit lässt sich das Fenster ansehen, ohne
    /// einen echten Termin anzulegen. Im Release-Build gibt es diesen Weg nicht.
    /// `screens` direkt aus den Einstellungen: Die Demo kann vor dem ersten `sync` laufen.
    func showDemoIfRequested(screens: FullScreenScreens) {
        guard ProcessInfo.processInfo.arguments.contains("-vollbildDemo") else { return }
        Self.log.notice("Vollbild-Demo angefordert")
        presenter.screens = screens
        let now = Date()
        presenter.show([
            AgendaItem(id: "demo.1", title: "Jour fixe CINEWEB", start: now.addingTimeInterval(60),
                       end: now.addingTimeInterval(1860), isAllDay: false, hasTime: true,
                       kind: .event, sourceID: "demo", color: .fallback, hasAlarms: true,
                       link: URL(string: "https://zoom.us/j/123456789")),
            AgendaItem(id: "demo.2", title: "Rückruf Kino Ottobrunn", start: now.addingTimeInterval(60),
                       end: nil, isAllDay: false, hasTime: true, kind: .event,
                       sourceID: "demo", color: .fallback, hasAlarms: false)
        ])
    }
    #endif

    // MARK: - Regeln (rein, ohne Uhr testbar)

    /// Darf ein Termin überhaupt einen Vollbild-Hinweis bekommen?
    /// Ganztägig: „beginnt gleich" ist bedeutungslos. Abgelehnt: sonst könnte eine
    /// fremde Einladung den Bildschirm sperren.
    nonisolated static func isEligible(_ item: AgendaItem) -> Bool {
        guard case .event = item.kind, !item.isAllDay, !item.isDeclined,
              item.start != nil else { return false }
        return true
    }

    /// Termine, deren Hinweiszeitpunkt noch in der Zukunft liegt (dafür wird ein
    /// Timer gestellt).
    nonisolated static func upcoming(in horizon: [AgendaItem], now: Date,
                                     lead: TimeInterval) -> [AgendaItem] {
        horizon.filter { item in
            guard isEligible(item), let start = item.start else { return false }
            return start.addingTimeInterval(-lead) > now
        }
    }

    /// Termine, die **jetzt** gezeigt werden müssen: Hinweiszeitpunkt erreicht,
    /// Beginn höchstens `grace` her, noch nicht gezeigt. Sortiert nach Beginn.
    nonisolated static func due(in horizon: [AgendaItem], now: Date, lead: TimeInterval,
                                shown: Set<String>) -> [AgendaItem] {
        horizon.filter { item in
            guard isEligible(item), let start = item.start,
                  !shown.contains(item.id) else { return false }
            return start.addingTimeInterval(-lead) <= now && now < start.addingTimeInterval(grace)
        }
        .sorted { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
    }

    /// Unter diesem Abstand zum Beginn lohnt „Zum Beginn nochmal" nicht mehr — der
    /// Hinweis käme praktisch sofort wieder. Der Knopf wird dann ausgeblendet.
    nonisolated static let minSnooze: TimeInterval = 30

    /// Termine aus einem offenen Hinweis, die zum Beginn noch einmal kommen können.
    nonisolated static func snoozable(_ items: [AgendaItem], now: Date) -> [AgendaItem] {
        items.filter { item in
            guard isEligible(item), let start = item.start else { return false }
            return start.timeIntervalSince(now) >= minSnooze
        }
    }

    /// Geschlummerte Termine, die **jetzt** zum Beginn erneut erscheinen: Beginn erreicht,
    /// höchstens `grace` her (z. B. nach dem Ruhezustand).
    nonisolated static func snoozeDue(in horizon: [AgendaItem], now: Date,
                                      snoozed: Set<String>) -> [AgendaItem] {
        horizon.filter { item in
            guard isEligible(item), snoozed.contains(item.id), let start = item.start else { return false }
            return start <= now && now < start.addingTimeInterval(grace)
        }
        .sorted { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
    }
}

/// Auf welchen Bildschirmen der Vollbild-Hinweis erscheint (Michael, 2026-10-08).
///
/// „Hauptbildschirm" ist der mit der Menüleiste (`NSScreen.screens.first`), wie macOS
/// ihn in den Systemeinstellungen nennt — nicht `NSScreen.main`, das ist der Bildschirm
/// mit dem gerade aktiven Fenster und wechselt mit der Arbeit.
enum FullScreenScreens: Int, CaseIterable, Identifiable {
    case all = 0
    case main = 1
    case others = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .all: "Alle Bildschirme"
        case .main: "Hauptbildschirm (mit Menüleiste)"
        case .others: "Andere Bildschirme"
        }
    }

    /// Wählt aus `screens` (erstes Element = Hauptbildschirm) die Ziele. Nie leer, solange
    /// ein Bildschirm da ist: „Andere" ohne zweiten Bildschirm (MacBook unterwegs) fällt
    /// auf den Hauptbildschirm zurück — sonst käme der Hinweis unsichtbar.
    func targets<Screen>(in screens: [Screen]) -> [Screen] {
        guard let primary = screens.first else { return [] }
        switch self {
        case .all: return screens
        case .main: return [primary]
        case .others: return screens.count > 1 ? Array(screens.dropFirst()) : [primary]
        }
    }
}

/// Findet den Beitreten-Link eines Termins.
///
/// **Sicherheitsgrenze:** Kalenderdaten können aus fremden Einladungen stammen. Geöffnet
/// wird nur `http`/`https` mit Host. Andere Schemata (`file:`, `smb:`, App-Schemata)
/// können Programme starten oder Laufwerke einbinden. Keine Liste bekannter Dienste,
/// damit keine Dauerpflege entsteht (siehe „Draußen" in der Projektdatei).
enum MeetingLink {

    /// Obergrenze für den durchsuchten Text. Notizen können beliebig lang sein.
    nonisolated static let maxScannedCharacters = 10_000

    /// Reihenfolge: URL-Feld, dann Ort, dann Notizen — jeweils der erste gültige Link.
    nonisolated static func find(url: URL?, location: String?, notes: String?) -> URL? {
        if let url, isOpenable(url) { return url }
        for text in [location, notes] {
            if let text, let link = firstWebLink(in: text) { return link }
        }
        return nil
    }

    nonisolated static func isOpenable(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = url.host, !host.isEmpty else { return false }
        return true
    }

    nonisolated static func firstWebLink(in text: String) -> URL? {
        let limited = String(text.prefix(maxScannedCharacters))
        guard let detector = try? NSDataDetector(
            types: NSTextCheckingResult.CheckingType.link.rawValue
        ) else { return nil }
        let range = NSRange(limited.startIndex..., in: limited)
        for match in detector.matches(in: limited, range: range) {
            if let url = match.url, isOpenable(url) { return url }
        }
        return nil
    }
}
