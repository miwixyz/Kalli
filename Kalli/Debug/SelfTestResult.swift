#if DEBUG
import Foundation

/// Ergebnis-Teil des Selbsttests (getrennt von `SelfTest.swift`, damit das Testziel ihn ohne Brücke, Fenster und
/// Speicher kompilieren kann – wie `DebugCommand`).
@MainActor
enum SelfTest {
    struct Step {
        let name: String
        let ok: Bool
        let detail: String
    }

    /// Antwort für `Antworten/<id>.json`: `bestanden` plus `schritte`. Ohne Schritte gilt es nicht als bestanden.
    static func answer(_ steps: [Step]) -> [String: Any] {
        ["ok": true,
         "bestanden": !steps.isEmpty && steps.allSatisfy(\.ok),
         "schritte": steps.map { ["name": $0.name, "ok": $0.ok, "detail": $0.detail] as [String: Any] }]
    }
}
#endif
