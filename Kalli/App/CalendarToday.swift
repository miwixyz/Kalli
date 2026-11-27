import AppKit
import OSLog

/// Klick aufs Widget „Tagesblatt“ öffnet Apple Kalender am heutigen Tag (Michael 2026-11-27).
///
/// Kalli ist eine reine Menüleisten-App ohne Fenster: Ohne Klickziel machte der Widget-Klick
/// Kalli nur aktiv, sichtbar passierte nichts. Das Widget trägt deshalb den festen Link
/// `kalli://kalender-heute`, Kalli nimmt ihn an und schickt Apple Kalender auf heute.
///
/// Eng gehalten, weil ein URL-Schema Eingaben von außen annimmt (jede App und jede Webseite
/// kann einen `kalli:`-Link öffnen):
/// - Angenommen wird nur genau dieser eine Link, ohne Pfad, Abfrage oder Anker. Alles andere
///   wird ignoriert und protokolliert.
/// - Der Link trägt keine Daten; das Skript ist fester Text ohne Parameter, Ziel fest Apple Kalender.
///   Schlimmstenfalls öffnet ein fremder Link also Kalender in der Tagesansicht von heute.
/// - Das Skript läuft nicht auf dem Hauptthread und hat 60 Sekunden Zeitlimit: Beim ersten Klick
///   fragt macOS „Kalli darf Kalender steuern?“, und das Skript wartet auf die Antwort. Mit 5 Sekunden
///   lief es während des Dialogs ab (gemessen 2026-11-27, Fehler -1712).
/// - Fehlt die Erlaubnis „Kalli darf Kalender steuern“ oder scheitert das Skript, öffnet Kalli
///   Kalender trotzdem (ohne Tageswahl) und protokolliert den Grund.
nonisolated enum CalendarToday {
    static let url = URL(string: "kalli://kalender-heute")!

    private static let log = Logger(subsystem: "com.kalli.app", category: "widget-klick")
    private static let queue = DispatchQueue(label: "com.kalli.app.kalender-heute", qos: .userInitiated)
    private static let calendarBundleID = "com.apple.iCal"

    static let source = """
    with timeout of 60 seconds
        tell application "Calendar"
            switch view to day view
            view calendar at (current date)
        end tell
    end timeout
    """

    /// Nur genau `kalli://kalender-heute`, Groß-/Kleinschreibung von Schema und Host egal.
    static func matches(_ candidate: URL) -> Bool {
        guard let parts = URLComponents(url: candidate, resolvingAgainstBaseURL: false) else { return false }
        return parts.scheme?.lowercased() == "kalli"
            && parts.host?.lowercased() == "kalender-heute"
            && parts.user == nil && parts.password == nil && parts.port == nil
            && (parts.path.isEmpty || parts.path == "/")
            && parts.query == nil && parts.fragment == nil
    }

    @MainActor
    static func handle(_ urls: [URL]) {
        for candidate in urls {
            if matches(candidate) {
                log.notice("Widget-Klick: Kalender auf heute")
                open()
            } else {
                // Nur Schema und Host ins Protokoll, nie den Rest (fremde Eingabe).
                log.notice("Link ignoriert: \(candidate.scheme ?? "-", privacy: .public)://\(candidate.host ?? "-", privacy: .public)")
            }
        }
    }

    private static func open() {
        queue.async {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            if let error {
                let number = error[NSAppleScript.errorNumber] as? Int ?? 0
                log.error("Kalender-Skript gescheitert (\(number, privacy: .public)), öffne Kalender ohne Tageswahl")
            } else {
                log.notice("Kalender zeigt heute")
            }
            DispatchQueue.main.async { bringToFront() }
        }
    }

    /// Kalender nach vorn holen. `activate` im Skript reicht nicht: Seit macOS 14 darf eine
    /// Hintergrund-App eine andere App nicht einfach nach vorn holen (gemessen 2026-11-27: Kalender
    /// stellte sich auf heute, blieb aber hinten). Kalli gibt den Vordergrund deshalb ausdrücklich an
    /// Kalender ab und öffnet ihn dann über das System.
    @MainActor
    private static func bringToFront() {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: calendarBundleID) else {
            log.error("Apple Kalender nicht gefunden")
            return
        }
        NSApp.yieldActivation(toApplicationWithBundleIdentifier: calendarBundleID)
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: app, configuration: config) { running, error in
            if let error {
                log.error("Kalender nicht geöffnet: \(error.localizedDescription, privacy: .public)")
            } else {
                log.notice("Kalender nach vorn, aktiv \(running?.isActive ?? false, privacy: .public)")
            }
        }
    }
}

/// Nimmt Links an, die macOS an Kalli schickt (Widget-Klick). Siehe `CalendarToday`.
final class KalliAppDelegate: NSObject, NSApplicationDelegate {
    func application(_ application: NSApplication, open urls: [URL]) {
        CalendarToday.handle(urls)
    }
}
