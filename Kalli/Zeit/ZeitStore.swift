import Foundation
import OSLog

/// Speichert die Zeiterfassung als `zeit.json` in „Application Support/Kalli“.
///
/// Anders als in MacStd (dort blieb eine beschädigte Datei unbemerkt und wurde beim nächsten Speichern
/// überschrieben): Lässt sich die Datei nicht lesen, wird sie **zur Seite gelegt** (`zeit-defekt-<Zeit>.json`),
/// der Fehler gemeldet und erst dann leer gestartet. Daten gehen so nie still verloren.
struct ZeitStore {

    enum LoadResult {
        case ok(ZeitDaten)
        /// Datei war unlesbar, liegt jetzt unter `savedAs`; es geht leer weiter.
        case recovered(ZeitDaten, savedAs: URL?, reason: String)
    }

    let url: URL
    private static let log = Logger(subsystem: "com.kalli.app", category: "zeit")

    static func standardURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        // Echtes Kalli: „Kalli“. Jede andere Kennung (Bild-Testkopie, Selbsttest) bekommt einen eigenen Ordner,
        // damit Tests nie die echten Zeiten anfassen.
        let id = Bundle.main.bundleIdentifier ?? "Kalli"
        let folder = id == "com.kalli.app" ? "Kalli" : id
        return base.appendingPathComponent(folder, isDirectory: true).appendingPathComponent("zeit.json")
    }

    private var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    func load() -> LoadResult {
        guard FileManager.default.fileExists(atPath: url.path) else { return .ok(ZeitDaten()) }
        do {
            let data = try Data(contentsOf: url)
            return .ok(try decoder.decode(ZeitDaten.self, from: data))
        } catch {
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let aside = url.deletingLastPathComponent().appendingPathComponent("zeit-defekt-\(stamp).json")
            var saved: URL?
            do {
                try FileManager.default.moveItem(at: url, to: aside)
                saved = aside
            } catch {
                Self.log.error("Defekte zeit.json ließ sich nicht zur Seite legen: \(error.localizedDescription, privacy: .public)")
            }
            Self.log.error("zeit.json unlesbar: \(error.localizedDescription, privacy: .public)")
            return .recovered(ZeitDaten(), savedAs: saved, reason: error.localizedDescription)
        }
    }

    func save(_ daten: ZeitDaten) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(daten).write(to: url, options: [.atomic])
    }
}
