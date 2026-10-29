import Foundation

/// Bild-Testkopie (docs/SECURE-DESIGN.md K1): Debug-Build mit eigener Kennung, damit ihre
/// Bildschirmaufnahme-Freigabe nicht auch für das echte Kalli gilt. Sie startet nur Fenster + Befehlskanal –
/// kein Updater, keine Verbindung zu Gnotchi, kein Dienste-Menü.
///
/// Im Release-Build gibt es den Zweig nicht: `isActive` ist dort immer `false`, die Kennung steht nicht im Binary.
enum BildKopie {
    static var isActive: Bool {
        #if DEBUG
        Bundle.main.bundleIdentifier == "dev.mwlr.kalli.bild"
        #else
        false
        #endif
    }
}
