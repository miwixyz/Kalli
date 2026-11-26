import AppKit
import OSLog

/// Spielt `kalli.caf` (App-Familie: Blatt-Schnippen + Ton, 0,24 s), wenn der
/// Vollbild-Hinweis erscheint. Nur mit Einstellung „Ton zum Hinweis“ (ab Werk aus).
///
/// Bewusst nicht bei der Systemmitteilung: Die bringt ihren eigenen Ton mit, und
/// Kalli erfährt nicht zuverlässig, wann macOS sie zeigt. Den Vollbild-Hinweis
/// zeigt Kalli selbst, zum geplanten Zeitpunkt, genau einmal je Termin.
///
/// Scheitert nie stumm: fehlende oder unlesbare Datei landet im Protokoll.
@MainActor
enum AlertSound {
    static let resourceName = "kalli"
    static let resourceExtension = "caf"

    /// Messpunkt: `log show --last 30m --predicate 'subsystem == "com.kalli.app"'`
    private static let log = Logger(subsystem: "com.kalli.app", category: "ton")

    /// Gehalten, damit der Ton nicht während des Abspielens freigegeben wird.
    private static var current: NSSound?

    static func play() {
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: resourceExtension) else {
            log.notice("Ton fehlt: \(resourceName, privacy: .public).\(resourceExtension, privacy: .public) nicht im App-Bündel")
            return
        }
        guard let sound = NSSound(contentsOf: url, byReference: true) else {
            log.notice("Ton ließ sich nicht laden: \(url.lastPathComponent, privacy: .public)")
            return
        }
        current?.stop()
        current = sound
        if sound.play() {
            log.notice("Ton zum Vollbild-Hinweis gespielt")
        } else {
            log.notice("Ton zum Vollbild-Hinweis startete nicht")
        }
    }
}
