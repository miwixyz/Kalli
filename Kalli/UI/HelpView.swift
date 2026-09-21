import SwiftUI

/// Hilfe, Änderungen und rechtliche Hinweise — **direkt aus dem Bundle gelesen**,
/// nicht als Swift-Strings gepflegt.
///
/// Warum das der Kern der Sache ist: Tippis Hilfe hing an einem Tag fünf
/// Versionen hinterher, weil sie im Code stand und beim Release niemand
/// mitzog. Eine Prosa-Doku im Quelltext driftet immer — sie ist eine Kopie,
/// und Kopien veralten.
///
/// Hier liegen `HILFE.md`, `CHANGELOG.md` und `RECHTLICHES.md` als Ressourcen
/// im App-Bundle. `make build` kopiert sie bei **jedem** Durchlauf frisch aus
/// dem Repo. Damit kann die angezeigte Hilfe gar nicht älter sein als der Build,
/// und die Versionsnummer kommt aus der `Info.plist` statt aus einer Konstante.
struct HelpView: View {

    enum Doc: String, CaseIterable, Identifiable {
        case help = "Hilfe"
        case changes = "Änderungen"
        case legal = "Rechtliches"
        var id: String { rawValue }

        var resource: String {
            switch self {
            case .help: "HILFE"
            case .changes: "CHANGELOG"
            case .legal: "RECHTLICHES"
            }
        }
    }

    @State private var doc: Doc = .help

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "Version \(v) (Build \(b))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("", selection: $doc) {
                ForEach(Doc.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            ScrollView {
                Text(markdown(for: doc))
                    .font(.callout)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 2)
            }
            .frame(height: 300)

            Text(version)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    /// Liest die Datei aus dem Bundle und wandelt sie in `AttributedString`.
    ///
    /// Fehlt die Datei, steht das sichtbar da — statt einer leeren Fläche, die
    /// wie „keine Änderungen" aussieht. Ein fehlendes Dokument ist ein
    /// Build-Fehler, kein Anzeigezustand.
    private func markdown(for doc: Doc) -> AttributedString {
        guard let url = Bundle.main.url(forResource: doc.resource, withExtension: "md"),
              let raw = try? String(contentsOf: url, encoding: .utf8) else {
            return AttributedString(
                "„\(doc.resource).md" + "\" fehlt im App-Bundle. "
                + "Das ist ein Fehler beim Bauen, keine leere Datei."
            )
        }
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return (try? AttributedString(markdown: raw, options: options))
            ?? AttributedString(raw)
    }
}
