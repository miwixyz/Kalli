#if DEBUG
import Foundation

/// Ein Befehl an die Bild-Testkopie (docs/SECURE-DESIGN.md K1). Feste Liste, alles andere ist ungültig.
struct DebugCommand: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// Version, Kennung, Freigaben, offene eigene Fenster – nur Zahlen und Kennungen.
        case status
        /// Bild eines eigenen Fensters (nur Einstellungen und Hilfe – nie Kalender, Agenda, „die eine Sache“).
        case snapshot(window: String)
        /// Hell, dunkel oder wie das System.
        case appearance(String)
    }

    let id: String
    let kind: Kind

    static let settingsWindow = "einstellungen"
    static let helpWindow = "hilfe"
    /// Fenster, von denen ein Bild erlaubt ist. Kalender, Agenda und „die eine Sache“ zeigen im echten Kalli echte
    /// Inhalte und fehlen bewusst.
    static let snapshotWindows: Set<String> = [settingsWindow, helpWindow]
    static let appearances: Set<String> = ["light", "dark", "system"]

    /// Größte Nachricht (4 Byte Länge + JSON). Größer → Verbindung zu.
    static let maxFrame = 4096

    /// Nur das Developer-ID-signierte Steuerprogramm `kallictl` (Team LTKJ6Z2VYB) darf Befehle schicken.
    /// Nicht nur `anchor apple generic`: Apple-Development-Builds tragen `get-task-allow`.
    static let ctlRequirement =
        #"anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] and "#
        + #"certificate leaf[field.1.2.840.113635.100.6.1.13] and identifier "dev.mwlr.kalli.ctl" and "#
        + #"certificate leaf[subject.OU] = "LTKJ6Z2VYB""#

    /// `{"v":1,"id":"…","cmd":"status"|"snapshot"|"appearance", …}`; `id` 1–32 Zeichen a–z, A–Z, 0–9 (wird Dateiname).
    static func parse(_ payload: Data) -> DebugCommand? {
        guard let obj = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
              let v = obj["v"] as? NSNumber, CFGetTypeID(v) != CFBooleanGetTypeID(), v.doubleValue == 1,
              let id = obj["id"] as? String, (1...32).contains(id.count),
              id.unicodeScalars.allSatisfy({ $0.isASCII && CharacterSet.alphanumerics.contains($0) }),
              let cmd = obj["cmd"] as? String else { return nil }
        switch cmd {
        case "status":
            return DebugCommand(id: id, kind: .status)
        case "snapshot":
            guard let w = obj["window"] as? String, snapshotWindows.contains(w) else { return nil }
            return DebugCommand(id: id, kind: .snapshot(window: w))
        case "appearance":
            guard let m = obj["mode"] as? String, appearances.contains(m) else { return nil }
            return DebugCommand(id: id, kind: .appearance(m))
        default:
            return nil
        }
    }

    enum Frame: Equatable {
        case message(Data), needMore, invalid
    }

    /// Nimmt die nächste vollständige Nachricht vorne aus `buffer`. `invalid`: Länge 0 oder größer als `maxFrame` –
    /// der Server trennt dann die Verbindung.
    static func nextFrame(_ buffer: inout Data) -> Frame {
        guard buffer.count >= 4 else { return .needMore }
        let b = [UInt8](buffer.prefix(4))
        let length = Int(b[0]) << 24 | Int(b[1]) << 16 | Int(b[2]) << 8 | Int(b[3])
        guard length > 0, length + 4 <= maxFrame else { return .invalid }
        guard buffer.count >= length + 4 else { return .needMore }
        let payload = Data(buffer.dropFirst(4).prefix(length))
        buffer = Data(buffer.dropFirst(4 + length))
        return .message(payload)
    }

    static func frame(_ object: [String: Any]) -> Data? {
        guard let json = try? JSONSerialization.data(withJSONObject: object), json.count + 4 <= maxFrame else { return nil }
        return withUnsafeBytes(of: UInt32(json.count).bigEndian) { Data($0) } + json
    }
}
#endif
