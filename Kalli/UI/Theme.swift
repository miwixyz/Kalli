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

    // MARK: - Schrift

    /// Schriftgrößen als Punktwerte, damit sie sich skalieren lassen.
    ///
    /// **Warum nicht `.callout`, `.caption` & Co. mit `dynamicTypeSize`:**
    /// Dynamic Type ist ein iOS-Mechanismus. Auf macOS haben die semantischen
    /// Textstile feste Größen und reagieren nicht darauf — der Modifier läuft
    /// wirkungslos durch. Gemessen am 2026-09-21: Die Fensterbreite wuchs
    /// (eigener Faktor), die Schrift blieb stehen.
    ///
    /// Deshalb hier feste Basiswerte, die überall mit demselben Faktor
    /// multipliziert werden. Eine Stelle, ein Faktor, keine Drift.
    enum Size {
        static let monthTitle: CGFloat = 15
        static let dayNumber: CGFloat = 15
        static let weekday: CGFloat = 11
        static let weekNumber: CGFloat = 10
        static let groupTitle: CGFloat = 10
        static let dayHeader: CGFloat = 12
        static let itemTitle: CGFloat = 13
        static let itemTime: CGFloat = 11
        static let hint: CGFloat = 10
        static let bannerTitle: CGFloat = 13
    }

    static func font(_ size: CGFloat, _ scale: Double,
                     weight: Font.Weight = .regular) -> Font {
        .system(size: size * scale, weight: weight)
    }

    /// Radius für Karten und Hinweisflächen. Großzügiger als der macOS-Standard,
    /// weil Liquid Glass weichere Formen verlangt.
    static let cardRadius: CGFloat = 11
}
