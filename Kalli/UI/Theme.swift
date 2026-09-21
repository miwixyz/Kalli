import SwiftUI

/// Kallis Farben und Formen an einer Stelle.
///
/// Warum nicht `Color.accentColor`: Das ist die System-Akzentfarbe, also das
/// macOS-Standardblau. Es wirkt neben modernen Oberflächen flach und beliebig,
/// weil es seit Jahren unverändert ist und in jeder App gleich aussieht.
///
/// Kalli nutzt stattdessen das Blau aus der Tippi-Familie (`#3070F0`) — kräftiger,
/// etwas kühler, und es verbindet die beiden Apps auch farblich. Wer lieber die
/// Systemfarbe will, ändert genau diese eine Zeile.
enum Theme {

    /// Markenblau, aus `tippi-spec.md` / `kalli-spec.md`.
    static let accent = Color(red: 0x30 / 255, green: 0x70 / 255, blue: 0xF0 / 255)

    /// Verlauf für gefüllte Flächen. Ein leichter Verlauf gibt Tiefe, wo eine
    /// Vollfarbe wie ein aufgeklebter Aufkleber wirkt.
    static var accentFill: LinearGradient {
        LinearGradient(
            colors: [accent, accent.opacity(0.78)],
            startPoint: .top, endPoint: .bottom
        )
    }

    /// Weicher Schein unter gefüllten Elementen — trägt die Tiefe, ohne einen
    /// harten Schlagschatten zu setzen.
    static let accentGlow = accent.opacity(0.38)

    /// Radius für Karten und Hinweisflächen. Großzügiger als der macOS-Standard,
    /// weil Liquid Glass weichere Formen verlangt.
    static let cardRadius: CGFloat = 11
}
