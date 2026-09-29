import SwiftUI

/// Eine Gruppe in den Einstellungen, im Stil der macOS-26-Systemeinstellungen:
/// farbiges Symbol-Quadrat als Überschrift, darunter eine zarte Karte.
///
/// **Warum eine Karte und kein Glas:** Die Einstellungen liegen schon auf der
/// Glasfläche des Popovers. Glas auf Glas mittelt die Farben weiter und macht
/// Text schlechter lesbar (siehe `GlassBackground`). Apple setzt in solchen
/// Fällen eine leicht getönte, gruppierte Fläche — genau das hier. Hell/Dunkel
/// folgt über `.primary` automatisch.
///
/// Schalter in der Karte erscheinen als Switch. Wer bewusst etwas anderes will
/// (die Kalenderlisten mit Häkchen), setzt den Stil am Element selbst.
struct SettingsGroup<Content: View>: View {
    let title: String
    let symbol: String
    let tint: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                SymbolTile(symbol: symbol, tint: tint)
                Text(title)
                    .font(Theme.font(12, 1, weight: .semibold))
            }
            .padding(.leading, 2)

            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.primary.opacity(0.045))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(.primary.opacity(0.07), lineWidth: 0.8)
                    }
            }
        }
    }
}

/// Weißes Symbol auf farbigem, weich gerundetem Quadrat — die Kennzeichnung
/// der Systemeinstellungen. Leichter Verlauf wie `Theme.accentFill`.
struct SymbolTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 20

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.55, weight: .semibold))
            .foregroundStyle(Theme.onAccent)
            .frame(width: size, height: size)
            .background {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(LinearGradient(colors: [tint, tint.opacity(0.8)],
                                         startPoint: .top, endPoint: .bottom))
            }
    }
}

/// Erklärtext unter einem Schalter. Eine Stelle für Größe und Farbe.
struct SettingsHint: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(Theme.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
