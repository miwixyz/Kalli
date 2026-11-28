import Foundation
import Observation

/// Zeiterfassung in Kalli (ab 0.21.0, aus MacStd übernommen): Projekte, Start/Stopp, Pause, Einträge,
/// Wochen-/Monatssummen. Eine laufende Erfassung steht sofort in der Datei und übersteht Absturz,
/// Abmelden und Ausschalten; „Beenden“ von Kalli bucht sie bis jetzt als Eintrag.
@MainActor
@Observable
final class ZeitErfassung {

    enum Zeitraum: String, CaseIterable, Identifiable {
        case woche, monat
        var id: String { rawValue }
        var titel: String { self == .woche ? "Woche" : "Monat" }
    }

    private(set) var projects: [ZeitProjekt] = []
    private(set) var entries: [ZeitEintrag] = []
    private(set) var activeProjectID: UUID?
    private(set) var sessionStart: Date?
    private(set) var sessionPauses: [ZeitPause] = []
    private(set) var pauseStart: Date?
    /// Kommentar zur laufenden Erfassung; wandert beim Stoppen in den Eintrag.
    private(set) var sessionNote = ""
    /// Sichtbare Fehlermeldung (Speichern, Laden, Wiederherstellen). Nie still.
    var errorMessage: String?
    /// Wie oft eine Nutzeraktion einen Ton angefordert hat (unabhängig vom Schalter). Für Tests.
    private(set) var soundRequests = 0

    private let store: ZeitStore
    /// Gesetzt, wenn eine unlesbare Datei nicht zur Seite gelegt werden konnte: Dann wird nie geschrieben,
    /// sonst ginge das Original beim nächsten Speichern verloren.
    private var saveBlocked = false
    private let now: @MainActor @Sendable () -> Date
    /// Wird nach jeder Änderung gerufen (Menüleiste neu zeichnen).
    var onChange: @MainActor @Sendable () -> Void = {}
    private let playSound: @MainActor @Sendable () -> Void
    private let soundEnabled: @MainActor @Sendable () -> Bool

    init(store: ZeitStore = ZeitStore(url: ZeitStore.standardURL()),
         now: @escaping @MainActor @Sendable () -> Date = { Date() },
         soundEnabled: @escaping @MainActor @Sendable () -> Bool = { false },
         playSound: @escaping @MainActor @Sendable () -> Void = {}) {
        self.store = store
        self.now = now
        self.soundEnabled = soundEnabled
        self.playSound = playSound
        load()
    }

    // MARK: - Zustand

    var hasActiveSession: Bool { sessionStart != nil && activeProjectID != nil }
    var isPaused: Bool { pauseStart != nil }

    enum Zustand { case steht, laeuft, pause }
    var zustand: Zustand { hasActiveSession ? (isPaused ? .pause : .laeuft) : .steht }

    var activeProject: ZeitProjekt? { projects.first { $0.id == activeProjectID } }

    func projectName(_ id: UUID) -> String { projects.first { $0.id == id }?.name ?? "Gelöschtes Projekt" }

    /// Netto-Zeit der laufenden Erfassung (ohne Pausen).
    func elapsed(at date: Date) -> TimeInterval {
        guard let start = sessionStart else { return 0 }
        var gross = date.timeIntervalSince(start)
        gross -= sessionPauses.reduce(0) { $0 + $1.duration }
        if let begin = pauseStart { gross -= date.timeIntervalSince(begin) }
        return max(0, gross)
    }

    // MARK: - Laden / Speichern

    private func load() {
        switch store.load() {
        case .ok(let daten):
            apply(daten)
        case .recovered(let daten, let saved, let reason):
            apply(daten)
            if let saved {
                errorMessage = "Die Zeitdatei war nicht lesbar (\(reason)). Sie liegt unverändert unter „\(saved.lastPathComponent)“ in Application Support/Kalli."
            } else {
                saveBlocked = true
                errorMessage = "Die Zeitdatei war nicht lesbar und ließ sich nicht sichern (\(reason)). "
                    + "Kalli speichert Zeiten nicht, bis sie geprüft ist (Application Support/Kalli/zeit.json)."
            }
        }
    }

    private func apply(_ daten: ZeitDaten) {
        projects = daten.projects
        entries = daten.entries
        restore(daten.activeSession)
    }

    /// Übernimmt eine gespeicherte laufende Erfassung nur, wenn ihr Projekt existiert und sie nicht in der Zukunft beginnt.
    private func restore(_ session: ZeitLaufend?) {
        guard let session else { return }
        guard projects.contains(where: { $0.id == session.projectID }), session.start <= now().addingTimeInterval(60) else {
            errorMessage = "Die laufende Erfassung vom letzten Start konnte nicht wiederhergestellt werden "
                + "(Projekt fehlt oder Startzeit liegt in der Zukunft)."
            save()
            return
        }
        activeProjectID = session.projectID
        sessionStart = session.start
        sessionPauses = session.pausesCompleted.filter { $0.start >= session.start && $0.end >= $0.start }
        pauseStart = session.pauseStart.flatMap { $0 >= session.start ? $0 : nil }
        sessionNote = session.note ?? ""
    }

    private var current: ZeitLaufend? {
        guard let projectID = activeProjectID, let start = sessionStart else { return nil }
        return ZeitLaufend(projectID: projectID, start: start, pausesCompleted: sessionPauses, pauseStart: pauseStart,
                          note: sessionNote.isEmpty ? nil : sessionNote)
    }

    private func save() {
        guard !saveBlocked else { onChange(); return }
        do {
            try store.save(ZeitDaten(projects: projects, entries: entries, activeSession: current))
        } catch {
            errorMessage = "Zeiten konnten nicht gespeichert werden: \(error.localizedDescription)"
        }
        onChange()
    }

    // MARK: - Projekte

    private static let palette = ["5E9EFF", "7C5CFF", "34C759", "FF9F0A", "FF453A", "64D2FF"]

    @discardableResult
    func addProject(name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        projects.append(ZeitProjekt(name: trimmed, colorHex: Self.palette[projects.count % Self.palette.count]))
        save()
        return true
    }

    func renameProject(id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let i = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[i].name = trimmed
        save()
    }

    func deleteProject(id: UUID) {
        if activeProjectID == id { clearSession() }
        projects.removeAll { $0.id == id }
        entries.removeAll { $0.projectID == id }
        save()
    }

    // MARK: - Erfassung

    /// Start/Stopp beim Projekt (Nutzeraktion). Ein Projektwechsel klingt einmal.
    func toggle(projectID: UUID) {
        defer { requestSound() }
        if hasActiveSession, activeProjectID == projectID {
            finishSession()
        } else {
            if hasActiveSession { finishSession() }
            begin(projectID: projectID)
        }
    }

    /// „Stoppen“ per Knopf: bucht den Eintrag, dazu der Ton.
    func stopByUser() {
        guard hasActiveSession else { return }
        finishSession()
        requestSound()
    }

    func pause() {
        guard hasActiveSession, pauseStart == nil else { return }
        pauseStart = now()
        save()
    }

    func resume() {
        guard let begin = pauseStart else { return }
        sessionPauses.append(ZeitPause(start: begin, end: now()))
        pauseStart = nil
        save()
    }

    /// Kalli beendet: eine laufende Erfassung wird bis jetzt gebucht (Feierabend), sonst zählte die Nacht mit.
    func prepareForQuit() {
        if hasActiveSession { finishSession() }
    }

    private func begin(projectID: UUID) {
        guard projects.contains(where: { $0.id == projectID }) else { return }
        activeProjectID = projectID
        sessionStart = now()
        sessionPauses = []
        pauseStart = nil
        sessionNote = ""
        save()
    }

    private func finishSession() {
        guard let start = sessionStart, let projectID = activeProjectID else { clearSession(); save(); return }
        let end = now()
        var pauses = sessionPauses
        if let begin = pauseStart { pauses.append(ZeitPause(start: begin, end: end)) }
        if end > start {
            entries.append(ZeitEintrag(projectID: projectID, start: start, end: end,
                                       note: sessionNote.trimmingCharacters(in: .whitespacesAndNewlines), pauses: pauses))
        }
        clearSession()
        save()
    }

    private func clearSession() {
        sessionStart = nil
        activeProjectID = nil
        sessionPauses = []
        pauseStart = nil
        sessionNote = ""
    }

    /// Kommentar zur laufenden Erfassung setzen (wird sofort gespeichert).
    func setNote(_ note: String) {
        guard hasActiveSession, note != sessionNote else { return }
        sessionNote = String(note.prefix(500))
        save()
    }

    private func requestSound() {
        soundRequests += 1
        if soundEnabled() { playSound() }
    }

    // MARK: - Einträge

    /// Speichert einen bearbeiteten Eintrag. `false` (mit Meldung), wenn die Pausen länger sind als Von–Bis.
    @discardableResult
    func update(_ edited: ZeitEintrag) -> Bool {
        guard let i = entries.firstIndex(where: { $0.id == edited.id }) else { return false }
        let lo = min(edited.start, edited.end), hi = max(edited.start, edited.end)
        let merged = Self.mergePauses(edited.pauses, start: lo, end: hi)
        if merged.reduce(0, { $0 + $1.duration }) > hi.timeIntervalSince(lo) + 0.5 {
            errorMessage = "Die Pausen übersteigen die Brutto-Dauer (Von–Bis). Bitte kürzen oder Zeiten anpassen."
            return false
        }
        entries[i] = ZeitEintrag(id: edited.id, projectID: edited.projectID, start: lo, end: hi,
                                 note: edited.note.trimmingCharacters(in: .whitespacesAndNewlines), pauses: merged)
        save()
        return true
    }

    func deleteEntry(id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    /// Pausen auf den Eintrag beschneiden, sortieren, Überlappungen zusammenführen.
    nonisolated static func mergePauses(_ pauses: [ZeitPause], start: Date, end: Date) -> [ZeitPause] {
        let clamped = pauses.compactMap { p -> ZeitPause? in
            guard p.end > p.start else { return nil }
            let s = max(p.start, start), e = min(p.end, end)
            return e > s ? ZeitPause(id: p.id, start: s, end: e) : nil
        }.sorted { $0.start < $1.start }
        guard var cur = clamped.first else { return [] }
        var out: [ZeitPause] = []
        for next in clamped.dropFirst() {
            if next.start <= cur.end {
                cur = ZeitPause(id: cur.id, start: cur.start, end: max(cur.end, next.end))
            } else {
                out.append(cur)
                cur = next
            }
        }
        out.append(cur)
        return out
    }

    // MARK: - Auswertung

    nonisolated static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "de_DE")
        c.firstWeekday = 2
        return c
    }

    nonisolated static func interval(_ z: Zeitraum, containing anchor: Date, calendar: Calendar = ZeitErfassung.calendar) -> DateInterval? {
        calendar.dateInterval(of: z == .woche ? .weekOfYear : .month, for: anchor)
    }

    nonisolated static func shift(_ anchor: Date, _ z: Zeitraum, by step: Int, calendar: Calendar = ZeitErfassung.calendar) -> Date {
        calendar.date(byAdding: z == .woche ? .weekOfYear : .month, value: step, to: anchor) ?? anchor
    }

    func entries(in interval: DateInterval) -> [ZeitEintrag] {
        entries.filter { $0.end > interval.start && $0.start < interval.end }.sorted { $0.start > $1.start }
    }

    func totalsByProject(in interval: DateInterval) -> [(project: ZeitProjekt, total: TimeInterval)] {
        let list = entries(in: interval)
        return projects.compactMap { p in
            let mine = list.filter { $0.projectID == p.id }
            return mine.isEmpty ? nil : (p, mine.reduce(0) { $0 + $1.netDuration })
        }
    }

    /// Heute gebuchte Netto-Zeit eines Projekts (laufende Erfassung nicht eingerechnet).
    func todayTotal(for id: UUID, calendar: Calendar = ZeitErfassung.calendar) -> TimeInterval {
        let day = calendar.startOfDay(for: now())
        guard let end = calendar.date(byAdding: .day, value: 1, to: day) else { return 0 }
        return entries(in: DateInterval(start: day, end: end)).filter { $0.projectID == id }.reduce(0) { $0 + $1.netDuration }
    }
}
