import AppKit
import OSLog
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

/// Hell, Dunkel oder wie das System (Michael, 2026-09-29).
///
/// Gesetzt über `NSApp.appearance` — damit gilt es für **alle** Fenster von Kalli
/// auf einmal: Popover, Einstellungen und Vollbild-Hinweis. Eine Stelle, kein
/// Fenster kann abweichen.
enum AppearanceMode: Int, CaseIterable, Identifiable {
    case system = 0
    case light = 1
    case dark = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Hell"
        case .dark: "Dunkel"
        }
    }

    var symbol: String {
        switch self {
        case .system: "circle.lefthalf.filled"
        case .light: "sun.max.fill"
        case .dark: "moon.fill"
        }
    }

    /// Reihenfolge beim Durchschalten mit dem Knopf im Popover.
    var next: AppearanceMode {
        AppearanceMode(rawValue: (rawValue + 1) % AppearanceMode.allCases.count) ?? .system
    }

    @MainActor
    func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        // Messpunkt: gewählt vs. tatsächlich wirksam.
        Logger(subsystem: "com.kalli.app", category: "darstellung").notice(
            "Erscheinungsbild \(title, privacy: .public) → wirksam: \(NSApp.effectiveAppearance.name.rawValue, privacy: .public)"
        )
    }
}
