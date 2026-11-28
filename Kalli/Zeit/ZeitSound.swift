import AppKit
import OSLog

/// Ton der App-Familie beim Starten und Stoppen per Knopf (`zeit.caf`, 0,2 s, aus MacStd übernommen).
/// Nur bei Nutzeraktion. Fehlt die Datei oder spielt sie nicht, steht es im Protokoll (Kategorie „ton“), nie stumm.
@MainActor
enum ZeitSound {
    private static let log = Logger(subsystem: "com.kalli.app", category: "ton")
    private static var sound: NSSound?

    static var isAvailable: Bool { Bundle.main.url(forResource: "zeit", withExtension: "caf") != nil }

    static func play() {
        if sound == nil {
            guard let url = Bundle.main.url(forResource: "zeit", withExtension: "caf") else {
                log.notice("Start/Stopp-Ton: zeit.caf fehlt im Bündel")
                return
            }
            sound = NSSound(contentsOf: url, byReference: true)
            if sound == nil { log.notice("Start/Stopp-Ton: zeit.caf nicht lesbar") }
        }
        sound?.stop()
        if sound?.play() == false { log.notice("Start/Stopp-Ton: Wiedergabe fehlgeschlagen") }
    }
}
