#if DEBUG
import Foundation

extension ZeitErfassung {
    /// Reiter „Zeit“ mit festen Beispieldaten für Bilder der Bild-Testkopie: eigene Wegwerf-Datei im Temp-Ordner,
    /// Projekte „Praxis“ und „Kino-Planung“, einige Einträge dieser Woche und eine laufende Erfassung.
    static func demo() -> ZeitErfassung {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("kalli-zeit-demo-\(UUID().uuidString)").appendingPathComponent("zeit.json")
        let now = Date()
        let praxis = ZeitProjekt(name: "Praxis", colorHex: "5E9EFF")
        let kino = ZeitProjekt(name: "Kino-Planung", colorHex: "FF9F0A")
        func entry(_ project: ZeitProjekt, hoursAgo: Double, minutes: Double, pause: Double = 0) -> ZeitEintrag {
            let start = now.addingTimeInterval(-hoursAgo * 3600)
            let end = start.addingTimeInterval(minutes * 60)
            let pauses = pause > 0 ? [ZeitPause(start: start.addingTimeInterval(1800), end: start.addingTimeInterval(1800 + pause * 60))] : []
            return ZeitEintrag(projectID: project.id, start: start, end: end, note: "", pauses: pauses)
        }
        let daten = ZeitDaten(
            projects: [praxis, kino],
            entries: [entry(praxis, hoursAgo: 30, minutes: 190, pause: 20), entry(kino, hoursAgo: 26, minutes: 95),
                      entry(praxis, hoursAgo: 5, minutes: 75)],
            activeSession: ZeitLaufend(projectID: kino.id, start: now.addingTimeInterval(-38 * 60), pausesCompleted: [], pauseStart: nil))
        try? ZeitStore(url: url).save(daten)
        return ZeitErfassung(store: ZeitStore(url: url))
    }
}
#endif
