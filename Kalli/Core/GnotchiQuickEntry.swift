import Foundation
import OSLog

/// Schnelleingabe aus Gnotchi (Gnotchi-Spezifikation 2026-11-19, SECURE-DESIGN G61): Gnotchi erkennt
/// „Zahnarzt morgen 15 Uhr“ und zeigt die Vorschau, **Kalli speichert** — Gnotchi hat keinen Zugriff auf
/// Kalender und Erinnerungen und soll ihn auch nicht bekommen.
///
/// Weg: dieselbe beidseitig geprüfte Verbindung wie bei den Terminen (`GnotchiEventSender`, G26). Neu sind zwei
/// Nachrichten Gnotchi → Kalli (`v:2`, `create` und `undo`) und Kallis Antwort `result`. Kalli vertraut Gnotchi
/// trotz Code-Prüfung nicht blind: jede Anfrage wird hier streng gelesen (keine fremden Felder, echte Zahlen und
/// Wahrheitswerte, Titel- und Zeitgrenzen), Anlagen sind gedrosselt, und `undo` löscht nur, was gerade eben über
/// diesen Weg entstand. Diese Datei ist rein (ohne EventKit) und getestet; das Speichern steht in
/// `GnotchiQuickEntry+EventKit`. Nie Titel ins Protokoll.
enum GnotchiQuickEntry {

    static let version = 2
    static let maxTitle = 200
    /// Ein Termin darf höchstens so lang sein (Gnotchi schickt ab Werk 1 h).
    static let maxDuration: TimeInterval = 24 * 3600
    /// Zeitfenster für Anfangszeiten: ab gestern bis in fünf Jahren.
    static let earliestOffset: TimeInterval = -24 * 3600
    static let latestOffset: TimeInterval = 5 * 365 * 24 * 3600
    /// Höchstens so viele Anlagen pro Minute.
    static let maxCreatesPerMinute = 20
    /// So lange nach dem Anlegen darf Gnotchi den Eintrag zurücknehmen (Gnotchi bietet ⌘Z ~1,5 s an).
    static let undoLifetime: TimeInterval = 30

    enum Kind: String, Equatable { case event, reminder }

    struct Create: Equatable {
        let id: UUID
        let kind: Kind
        let title: String
        let start: Date?
        let end: Date?
        let allDay: Bool
        let urgent: Bool
    }

    enum Request: Equatable {
        case create(Create)
        case undo(UUID)
    }

    /// Warum eine Anfrage abgelehnt wurde. `message` geht an Gnotchi und wird dort angezeigt.
    enum Rejection: Error, Equatable {
        case malformed, invalidTitle, invalidTime, tooMany, duplicate, unknownUndo

        var message: String {
            switch self {
            case .malformed: "Kalli hat die Anfrage nicht verstanden."
            case .invalidTitle: "Bitte einen Titel eingeben (höchstens 200 Zeichen)."
            case .invalidTime: "Diese Zeitangabe nimmt Kalli nicht an."
            case .tooMany: "Zu viele Einträge in kurzer Zeit. Bitte kurz warten."
            case .duplicate: "Dieser Eintrag wurde schon angelegt."
            case .unknownUndo: "Rückgängig geht nur direkt nach dem Speichern."
            }
        }
    }

    // MARK: Lesen

    /// Ist das eine Schnelleingabe-Nachricht (`v` Zahl 2, kein Wahrheitswert)? Alles andere ignoriert Kalli
    /// still, wie bisher alles, was nach Gnotchis `ok` kam.
    static func isVersion2(_ obj: [String: Any]?) -> Bool {
        guard let v = number(obj?["v"]) else { return false }
        return v == Double(version)
    }

    /// Kennung der Anfrage, auch wenn der Rest ungültig ist — damit die Ablehnung zuzuordnen ist.
    static func requestID(_ obj: [String: Any]?) -> UUID? {
        let body = (obj?["create"] ?? obj?["undo"]) as? [String: Any]
        return (body?["id"] as? String).flatMap(UUID.init(uuidString:))
    }

    /// Streng: genau ein Schlüssel neben `v`, keine unbekannten Felder, Typen exakt.
    static func parse(_ obj: [String: Any]?, now: Date) -> Result<Request, Rejection> {
        guard let obj, isVersion2(obj), obj.count == 2 else { return .failure(.malformed) }
        if let body = obj["undo"] {
            guard let body = body as? [String: Any], Set(body.keys) == ["id"],
                  let id = (body["id"] as? String).flatMap(UUID.init(uuidString:)) else { return .failure(.malformed) }
            return .success(.undo(id))
        }
        guard let body = obj["create"] as? [String: Any],
              Set(body.keys) == ["id", "kind", "title", "start", "end", "allDay", "urgent"],
              let id = (body["id"] as? String).flatMap(UUID.init(uuidString:)),
              let kind = (body["kind"] as? String).flatMap(Kind.init(rawValue:)),
              let rawTitle = body["title"] as? String,
              let allDay = bool(body["allDay"]), let urgent = bool(body["urgent"]),
              let start = optionalDate(body["start"]), let end = optionalDate(body["end"]) else {
            return .failure(.malformed)
        }
        guard let title = cleanTitle(rawTitle) else { return .failure(.invalidTitle) }
        let create = Create(id: id, kind: kind, title: title, start: start.value, end: end.value,
                            allDay: allDay, urgent: urgent)
        guard timesAreValid(create, now: now) else { return .failure(.invalidTime) }
        return .success(.create(create))
    }

    /// Getrimmt, 1–200 Zeichen, keine Steuerzeichen (auch keine Zeilenumbrüche). `nil` = abgelehnt.
    static func cleanTitle(_ raw: String) -> String? {
        let title = raw.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty, title.count <= maxTitle,
              !title.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) else { return nil }
        return title
    }

    /// Termin: Beginn Pflicht; mit Uhrzeit auch Ende, Ende nach Beginn, höchstens 24 h; ganztägig ohne Ende.
    /// Erinnerung: Beginn wahlweise (ohne = ohne Fälligkeit), nie ein Ende. Beginn im erlaubten Zeitfenster.
    static func timesAreValid(_ c: Create, now: Date) -> Bool {
        if let start = c.start {
            let offset = start.timeIntervalSince(now)
            guard offset >= earliestOffset, offset <= latestOffset else { return false }
        }
        switch c.kind {
        case .reminder:
            return c.end == nil && (c.start != nil || c.allDay == false)
        case .event:
            guard let start = c.start else { return false }
            if c.allDay { return c.end == nil }
            guard let end = c.end else { return false }
            let duration = end.timeIntervalSince(start)
            return duration > 0 && duration <= maxDuration
        }
    }

    // MARK: Antwort

    /// `{"v":2,"result":{"id":"…","ok":true}}` bzw. mit `"ok":false,"error":"…"`. Ohne lesbare Kennung `id: null`.
    static func reply(id: UUID?, rejection: Rejection?) -> [String: Any] {
        reply(id: id, error: rejection?.message)
    }

    static func reply(id: UUID?, error: String?) -> [String: Any] {
        var result: [String: Any] = ["id": id.map { $0.uuidString as Any } ?? NSNull(), "ok": error == nil]
        if let error { result["error"] = error }
        return ["v": version, "result": result]
    }

    // MARK: Typen streng

    /// Zahl, aber kein Wahrheitswert (`NSNumber` aus JSON ist beides) und endlich.
    static func number(_ value: Any?) -> Double? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        let d = n.doubleValue
        return d.isFinite ? d : nil
    }

    static func bool(_ value: Any?) -> Bool? {
        guard let n = value as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else { return nil }
        return n.boolValue
    }

    /// Hülle, damit „fehlt/ungültig“ (`nil`) und „ausdrücklich null“ (`Box(nil)`) unterscheidbar sind.
    struct Box { let value: Date? }

    static func optionalDate(_ value: Any?) -> Box? {
        if value is NSNull { return Box(value: nil) }
        guard let seconds = number(value) else { return nil }
        return Box(value: Date(timeIntervalSince1970: seconds))
    }
}

// MARK: - Drossel

/// Gleitendes Fenster: höchstens `limit` Anlagen in `window` Sekunden.
struct QuickEntryRateLimiter {
    let limit: Int
    let window: TimeInterval
    private var stamps: [Date] = []

    init(limit: Int = GnotchiQuickEntry.maxCreatesPerMinute, window: TimeInterval = 60) {
        self.limit = limit
        self.window = window
    }

    mutating func allow(now: Date) -> Bool {
        stamps.removeAll { now.timeIntervalSince($0) >= window }
        guard stamps.count < limit else { return false }
        stamps.append(now)
        return true
    }
}

// MARK: - Rückgängig-Liste

/// Nur im Speicher: welche Anfrage-Kennung welchen EventKit-Eintrag angelegt hat, höchstens `lifetime` Sekunden.
/// Damit löscht `undo` nie etwas Fremdes oder Älteres. Kennungen bleiben bis zum Ablauf gesperrt, auch nach
/// einem `undo` — dieselbe Anfrage legt nie zweimal an.
struct QuickEntryUndoLedger {
    struct Entry: Equatable {
        let identifier: String
        let kind: GnotchiQuickEntry.Kind
        let created: Date
        var undone = false
    }

    let lifetime: TimeInterval
    private var entries: [UUID: Entry] = [:]

    init(lifetime: TimeInterval = GnotchiQuickEntry.undoLifetime) { self.lifetime = lifetime }

    mutating func contains(_ id: UUID, now: Date) -> Bool {
        prune(now: now)
        return entries[id] != nil
    }

    mutating func record(_ id: UUID, identifier: String, kind: GnotchiQuickEntry.Kind, now: Date) {
        prune(now: now)
        entries[id] = Entry(identifier: identifier, kind: kind, created: now)
    }

    /// Eintrag zum Zurücknehmen, höchstens einmal. `nil` = unbekannt, abgelaufen oder schon zurückgenommen.
    mutating func takeForUndo(_ id: UUID, now: Date) -> Entry? {
        prune(now: now)
        guard var entry = entries[id], !entry.undone else { return nil }
        entry.undone = true
        entries[id] = entry
        return entry
    }

    /// Löschen ist fehlgeschlagen → wieder freigeben (der Eintrag existiert noch).
    mutating func restore(_ id: UUID) {
        entries[id]?.undone = false
    }

    private mutating func prune(now: Date) {
        entries = entries.filter { now.timeIntervalSince($0.value.created) < lifetime }
    }
}

// MARK: - Ablauf

/// Nimmt Gnotchis Anfragen an und antwortet. Prüfen, drosseln, Doppel abweisen, anlegen, merken; `undo` nur aus
/// der Rückgängig-Liste. Speichern und Löschen kommen als Closures herein (im Test ohne EventKit).
@MainActor
final class GnotchiQuickEntryService {

    typealias Create = @MainActor (GnotchiQuickEntry.Create) async -> Result<String, GnotchiQuickEntry.Failure>
    typealias Remove = @MainActor (String, GnotchiQuickEntry.Kind) async -> String?

    private static let log = Logger(subsystem: "com.kalli.app", category: "schnelleingabe")

    private let create: Create
    private let remove: Remove
    private let now: () -> Date
    private var limiter = QuickEntryRateLimiter()
    private var ledger = QuickEntryUndoLedger()
    /// Kennungen, deren Anlage gerade läuft — dieselbe Anfrage zweimal hintereinander legt nicht doppelt an.
    private var pending: Set<UUID> = []

    init(create: @escaping Create, remove: @escaping Remove, now: @escaping () -> Date = Date.init) {
        self.create = create
        self.remove = remove
        self.now = now
    }

    /// Antwort für Gnotchi, `nil` = keine Schnelleingabe-Nachricht (still ignorieren).
    func handle(_ obj: [String: Any]?) async -> [String: Any]? {
        guard GnotchiQuickEntry.isVersion2(obj) else { return nil }
        let t = now()
        switch GnotchiQuickEntry.parse(obj, now: t) {
        case .failure(let rejection):
            Self.log.notice("Schnelleingabe abgelehnt — \(String(describing: rejection), privacy: .public)")
            return GnotchiQuickEntry.reply(id: GnotchiQuickEntry.requestID(obj), rejection: rejection)
        case .success(.create(let entry)):
            return await handleCreate(entry, now: t)
        case .success(.undo(let id)):
            return await handleUndo(id, now: t)
        }
    }

    private func handleCreate(_ entry: GnotchiQuickEntry.Create, now t: Date) async -> [String: Any] {
        guard !pending.contains(entry.id), !ledger.contains(entry.id, now: t) else {
            Self.log.notice("Schnelleingabe abgelehnt — duplicate")
            return GnotchiQuickEntry.reply(id: entry.id, rejection: .duplicate)
        }
        guard limiter.allow(now: t) else {
            Self.log.notice("Schnelleingabe abgelehnt — tooMany")
            return GnotchiQuickEntry.reply(id: entry.id, rejection: .tooMany)
        }
        pending.insert(entry.id)
        defer { pending.remove(entry.id) }
        switch await create(entry) {
        case .failure(let failure):
            return GnotchiQuickEntry.reply(id: entry.id, error: failure.message)
        case .success(let identifier):
            ledger.record(entry.id, identifier: identifier, kind: entry.kind, now: now())
            return GnotchiQuickEntry.reply(id: entry.id, error: nil)
        }
    }

    private func handleUndo(_ id: UUID, now t: Date) async -> [String: Any] {
        guard let entry = ledger.takeForUndo(id, now: t) else {
            Self.log.notice("Schnelleingabe abgelehnt — unknownUndo")
            return GnotchiQuickEntry.reply(id: id, rejection: .unknownUndo)
        }
        if let message = await remove(entry.identifier, entry.kind) {
            ledger.restore(id)
            return GnotchiQuickEntry.reply(id: id, error: message)
        }
        return GnotchiQuickEntry.reply(id: id, error: nil)
    }
}
