import SwiftUI

/// Eine Stelle entscheidet, wie Kallis schwebende Flächen gefüllt werden.
///
/// Ab macOS 26 ist das Liquid Glass (`glassEffect`). Das Deployment-Target ist
/// 26.0, ein Fallback wäre also toter Code — deshalb gibt es keinen.
///
/// **Geltungsbereich (Apples HIG):** Liquid Glass gehört in die *funktionale*
/// Schicht — Bedienelemente, Navigation, kurzlebige Oberflächen. Bei Kalli sind
/// das zwei Orte: das Popover am Menüleisten-Icon und (ab 0.5.0) die untere
/// Hälfte des Vollbild-Hinweises. Beides sind schwebende, kurzlebige Flächen.
///
/// **Was hier bewusst NICHT passiert** (Lehre aus Tippi, 2026-09-14): Ganze
/// Fensterinhalte bekommen keine Transluzenz. Vollflächige Transluzenz mittelt
/// das Hintergrundbild auf seine *Durchschnittsfarbe* — auf einem lila
/// Schreibtisch werden Fenster rosa, und das Muster des Bildes verschwindet.
/// Der Austausch von `glassEffect` gegen `.regularMaterial` ändert daran
/// nichts, weil nicht das Material das Problem ist, sondern die Transluzenz
/// selbst. Finder, Mail und Notizen machen es umgekehrt: fester Fensterkörper,
/// transluzent nur die Seitenleiste. Das Einstellungsfenster von Kalli behält
/// deshalb seinen Standardhintergrund.
struct GlassBackground<S: Shape>: ViewModifier {
    let shape: S

    /// Ab 0.6.0 mit Schiefer-Tönung über dem Glas (`familyTintedGlass`). Reines Glas
    /// ließ das Schreibtischbild voll durchscheinen: pinkes Hintergrundbild → rosa
    /// Popover, weit weg von der Vorschau des Design-Systems (Michael, 29.09.).
    func body(content: Content) -> some View {
        content.familyTintedGlass(in: shape)
    }
}

extension View {
    /// Liquid Glass, beschnitten auf `shape`. Nur für schwebende Flächen.
    func glassSurface<S: Shape>(in shape: S) -> some View {
        modifier(GlassBackground(shape: shape))
    }

    /// Variante für Flächen, deren Fenster die äußere Form schon vorgibt.
    func glassSurface() -> some View {
        modifier(GlassBackground(shape: Rectangle()))
    }
}
