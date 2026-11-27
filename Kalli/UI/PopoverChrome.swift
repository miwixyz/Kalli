import SwiftUI

// Glas-Sprache der App-Familie für Kallis Popover (ab Knippi 0.7.0, Vault: „App-Familie Design-System“,
// Abschnitt „Glas-Sprache“). Der Hintergrund ist kein getöntes Glas mehr, sondern ein ruhig lebender
// Mesh-Verlauf mit Akzent-Glühen (`AmbientBackdrop`). Er ist deckend: Ein pinkes Schreibtischbild färbt
// das Popover nicht mehr ein (Lehre 0.6.0, `GlassBackground`). Inhalte liegen auf festen Karten,
// Schwebendes (Umschalter, Knopfgruppen) auf Glas.

extension View {
    /// Hintergrund des Popovers: lebender Verlauf, auf die Popover-Form beschnitten. Bei „Transparenz
    /// reduzieren“/„Kontrast erhöhen“ fester Familien-Verlauf, bei „Bewegung reduzieren“ stillstehend.
    func popoverChrome(cornerRadius: CGFloat = 14) -> some View {
        // Runde 3 (Michael 27.11.): Die Insel-Lichter sind für große Fenster bemessen (Ellipse 280 × 500).
        // Im 360 pt breiten Popover wurden sie mit Kallis dunklem Indigo zu einem schmutzigen Schrägbalken.
        // Deshalb nur der Verlauf, mit mittlerem Glühen.
        background {
            AmbientBackdrop(glow: 0.9)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    /// Feste Inhaltskarte (Regel G1): `card` mit feinem Rand und weichem Schatten.
    func familyContentCard(radius: CGFloat = 16) -> some View {
        modifier(FamilyContentCard(radius: radius))
    }
}

private struct FamilyContentCard: ViewModifier {
    let radius: CGFloat
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content.background {
            shape.fill(FamilyTheme.card)
                .overlay {
                    shape.strokeBorder(FamilyTheme.cardStroke.opacity(contrast == .increased ? 1 : 0.7),
                                       lineWidth: contrast == .increased ? 1 : 0.6)
                }
                .shadow(color: Color(light: 0x1E2846, dark: 0x000000).opacity(scheme == .dark ? 0.35 : 0.07),
                        radius: 8, y: 3)
        }
    }
}
