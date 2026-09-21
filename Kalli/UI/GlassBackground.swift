import SwiftUI

/// Eine Stelle entscheidet, wie Kallis schwebende Flächen gefüllt werden.
///
/// Ab macOS 26 ist das Liquid Glass (`glassEffect`). Das Deployment-Target ist
/// 26.0, ein Fallback wäre also toter Code — deshalb gibt es keinen.
///
/// **Geltungsbereich (Apples HIG):** Liquid Glass gehört in die *funktionale*
/// Schicht — Bedienelemente, Navigation, kurzlebige Oberflächen. Bei Kalli ist
/// das genau ein Ort: das Popover am Menüleisten-Icon. Ein Popover ist per
/// Definition eine schwebende Fläche, also ist es hier richtig platziert.
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

    func body(content: Content) -> some View {
        content.glassEffect(.regular, in: shape)
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
