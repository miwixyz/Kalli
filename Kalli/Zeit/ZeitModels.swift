import Foundation

// Datenmodell der Zeiterfassung (übernommen aus MacStd 1.4.0, Namen mit Zeit-Präfix, weil Kalli
// „Project“ u. Ä. nicht belegen soll). Dateiformat bleibt das von MacStd (Schema 3), damit eine
// `tracking.json` von dort unverändert lesbar wäre.

struct ZeitProjekt: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    var colorHex: String

    init(id: UUID = UUID(), name: String, colorHex: String = "5E9EFF") {
        self.id = id
        self.name = name
        self.colorHex = colorHex
    }
}

struct ZeitPause: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var start: Date
    var end: Date

    init(id: UUID = UUID(), start: Date, end: Date) {
        self.id = id
        self.start = start
        self.end = end
    }

    var duration: TimeInterval { max(0, end.timeIntervalSince(start)) }
}

struct ZeitEintrag: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var projectID: UUID
    var start: Date
    var end: Date
    var note: String
    var pauses: [ZeitPause]

    enum CodingKeys: String, CodingKey { case id, projectID, start, end, note, pauses }

    init(id: UUID = UUID(), projectID: UUID, start: Date, end: Date, note: String = "", pauses: [ZeitPause] = []) {
        self.id = id
        self.projectID = projectID
        self.start = start
        self.end = end
        self.note = note
        self.pauses = pauses
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        projectID = try c.decode(UUID.self, forKey: .projectID)
        start = try c.decode(Date.self, forKey: .start)
        end = try c.decode(Date.self, forKey: .end)
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        pauses = try c.decodeIfPresent([ZeitPause].self, forKey: .pauses) ?? []
    }

    var grossDuration: TimeInterval { max(0, end.timeIntervalSince(start)) }
    var pauseDurationTotal: TimeInterval { pauses.reduce(0) { $0 + $1.duration } }
    /// Netto-Arbeitszeit ohne Pausen.
    var netDuration: TimeInterval { max(0, grossDuration - pauseDurationTotal) }
}

/// Laufende Erfassung, damit sie einen Absturz oder Neustart übersteht.
struct ZeitLaufend: Codable, Hashable, Sendable {
    var projectID: UUID
    var start: Date
    var pausesCompleted: [ZeitPause]
    var pauseStart: Date?
    /// Kommentar zur laufenden Erfassung (ab 0.21.0). Fehlt in Dateien von MacStd → `nil`.
    var note: String?
}

enum ZeitFormat {
    /// Dauer für die Anzeige: unter einer Minute in Sekunden („42 s“), sonst „h:mm“. Früher stand jede Dauer
    /// unter 30 s als „0:00“ da und sah aus wie nicht gebucht.
    static func anzeige(_ interval: TimeInterval) -> String {
        let s = Int(interval.rounded())
        if s < 60 { return "\(s) s" }
        let m = s / 60
        return String(format: "%d:%02d", m / 60, m % 60)
    }
}

struct ZeitDaten: Codable, Sendable {
    var projects: [ZeitProjekt]
    var entries: [ZeitEintrag]
    var activeSession: ZeitLaufend?
    var schemaVersion: Int

    init(projects: [ZeitProjekt] = [], entries: [ZeitEintrag] = [], activeSession: ZeitLaufend? = nil, schemaVersion: Int = 3) {
        self.projects = projects
        self.entries = entries
        self.activeSession = activeSession
        self.schemaVersion = schemaVersion
    }
}
