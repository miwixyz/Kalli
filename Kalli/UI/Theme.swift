import AppKit
import OSLog
import SwiftUI

/// Kallis Farben und Formen an einer Stelle.
///
/// Ab 0.6.0 kommen Akzent und Schrift aus dem Design-System der App-Familie
/// (`FamilyTheme.swift`, Quelle der Wahrheit im Vault: „App-Familie
/// Design-System“): Farbwelt „Schiefer“, Schrift Plus Jakarta Sans, entschieden
/// mit Michael am 2026-09-29. Vorher: eigenes Blau `#3070F0` und SF Pro.
enum Theme {

    /// Kalli-Akzent „Schieferindigo“, hell `#3E4D98`, dunkel `#98A4E1`. Dynamisch,
    /// folgt Hell/Dunkel ohne Neuzeichnen von Hand.
    static var accent: Color { FamilyTheme.accent }

    /// Text/Symbol auf dem Akzent: hell Weiß, dunkel fast Schwarz — Weiß auf dem
    /// hellen Dunkelmodus-Akzent wäre kaum lesbar.
    static var onAccent: Color { FamilyTheme.onAccent }

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
    static var accentGlow: Color { accent.opacity(0.38) }

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

    /// Plus Jakarta Sans in fester Größe × Kalli-Skalierung (macOS kennt kein
    /// Dynamic Type, siehe oben). Ist die Schrift nicht registriert, fällt SwiftUI
    /// still auf die Systemschrift zurück — deshalb protokolliert der App-Start
    /// das Ergebnis von `FamilyTheme.registerFonts()`.
    static func font(_ size: CGFloat, _ scale: Double,
                     weight: Font.Weight = .regular) -> Font {
        .custom(FamilyTheme.fontFamily, fixedSize: size * scale).weight(weight)
    }

    /// Die früheren Systemstile (`.caption2`, `.callout` …) in Plus Jakarta Sans,
    /// mit den macOS-Größen dieser Stile. Nur für Stellen ohne Skalierung
    /// (Einstellungen, Hinweise).
    static let caption = font(10, 1)
    static let callout = font(12, 1)
    static let calloutSemibold = font(12, 1, weight: .semibold)

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
