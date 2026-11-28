import AppKit
import Foundation
import UniformTypeIdentifiers

/// Export der Zeiten als CSV (Semikolon, mit BOM für Excel) oder Markdown. Rein bis auf `speichern`.
enum ZeitExport {

    enum Format: String, CaseIterable, Identifiable {
        case csv, markdown
        var id: String { rawValue }
        var titel: String { self == .csv ? "CSV" : "Markdown" }
        var endung: String { self == .csv ? "csv" : "md" }
    }

    static func text(format: Format, entries: [ZeitEintrag], projects: [ZeitProjekt], titel: String, erzeugt: Date = Date()) -> String {
        let name: (UUID) -> String = { id in projects.first { $0.id == id }?.name ?? "Gelöschtes Projekt" }
        let sorted = entries.sorted { $0.start < $1.start }
        return format == .csv ? csv(sorted, name) : markdown(sorted, name, titel: titel, erzeugt: erzeugt)
    }

    private static func csv(_ entries: [ZeitEintrag], _ name: (UUID) -> String) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        iso.timeZone = TimeZone.current
        var rows = ["entry_id;project;start;end;net_seconds;gross_seconds;pause_seconds;note;pauses_iso"]
        for e in entries {
            let pauses = e.pauses.map { "\(iso.string(from: $0.start))/\(iso.string(from: $0.end))" }.joined(separator: "|")
            rows.append([e.id.uuidString, field(name(e.projectID)), iso.string(from: e.start), iso.string(from: e.end),
                         String(Int(e.netDuration.rounded())), String(Int(e.grossDuration.rounded())),
                         String(Int(e.pauseDurationTotal.rounded())), field(e.note), field(pauses)].joined(separator: ";"))
        }
        return "\u{FEFF}" + rows.joined(separator: "\n")
    }

    /// CSV-Feld; führende `= + - @ Tab` werden entschärft (Formel-Injektion in Excel/Numbers).
    static func field(_ raw: String) -> String {
        let safe = (raw.first.map { "=+-@\t".contains($0) } ?? false) ? "'" + raw : raw
        guard safe.contains(";") || safe.contains("\"") || safe.contains("\n") || safe.contains("\r") else { return safe }
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func dauer(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        return total >= 3600 ? "\(total / 3600)h \((total % 3600) / 60)m" : "\(total / 60)m"
    }

    private static func markdown(_ entries: [ZeitEintrag], _ name: (UUID) -> String, titel: String, erzeugt: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateStyle = .medium
        f.timeStyle = .short
        var lines = ["# Arbeitszeiten \(titel)", "", "_Export: \(f.string(from: erzeugt))_", ""]
        for e in entries {
            lines += ["## \(name(e.projectID))", "", "- **Von:** \(f.string(from: e.start))", "- **Bis:** \(f.string(from: e.end))",
                      "- **Netto:** \(dauer(e.netDuration))", "- **Brutto:** \(dauer(e.grossDuration))"]
            if !e.pauses.isEmpty {
                lines.append("- **Pausen:**")
                lines += e.pauses.map { "  - \(f.string(from: $0.start)) → \(f.string(from: $0.end)) (\(dauer($0.duration)))" }
            }
            if !e.note.isEmpty { lines.append("- **Notiz:** \(e.note)") }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    /// Fragt per Speichern-Dialog nach dem Ort und schreibt die Datei. Gibt eine Fehlermeldung zurück oder `nil`.
    @MainActor
    static func speichern(format: Format, text: String, vorschlag: String) -> String? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(vorschlag).\(format.endung)"
        if let type = UTType(filenameExtension: format.endung) { panel.allowedContentTypes = [type] }
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return nil
        } catch {
            return "Export fehlgeschlagen: \(error.localizedDescription)"
        }
    }
}
