import Foundation

/// Farbe als reine Zahlen statt als `CGColor`/`NSColor`.
///
/// Grund: EventKit-Objekte werden in einem Callback auf einer fremden Queue
/// ausgelesen. Alles, was diese Grenze überquert, muss `Sendable` sein — sonst
/// bleibt nur `assumeIsolated`, und das *prüft* nichts, es *behauptet*. Eine
/// falsche Behauptung ist ein harter Absturz (Lehre aus Tippi 2.11.5/2.11.6).
struct RGBA: Sendable, Hashable {
    let r: Double
    let g: Double
    let b: Double
    let a: Double

    static let fallback = RGBA(r: 0.5, g: 0.5, b: 0.5, a: 1)
}

/// Eine Quelle, die man ein- und ausblenden kann — Kalender oder Erinnerungsliste.
struct SourceInfo: Identifiable, Sendable, Hashable {
    enum Kind: String, Sendable, Hashable {
        case event
        case reminder
    }

    let id: String
    let title: String
    let color: RGBA
    let kind: Kind
    /// Name des Accounts (iCloud, Google, …) — zum Gruppieren in den Einstellungen.
    let sourceTitle: String
}

/// Ein Eintrag in der Tagesliste. Termin oder Erinnerung.
struct AgendaItem: Identifiable, Sendable, Hashable {
    enum Kind: Sendable, Hashable {
        case event
        case reminder(completed: Bool)
    }

    let id: String
    let title: String
    let start: Date?
    let end: Date?
    let isAllDay: Bool
    /// Ob `start` eine echte Uhrzeit trägt. Eine Erinnerung, die nur auf einen
    /// Tag fällig ist, liefert Mitternacht — das ist keine Uhrzeit, sondern die
    /// Abwesenheit einer. Ungeprüft steht dann überall „00:00".
    let hasTime: Bool
    let kind: Kind
    let sourceID: String
    let color: RGBA

    var isReminder: Bool {
        if case .reminder = kind { return true }
        return false
    }

    var isCompleted: Bool {
        if case .reminder(let done) = kind { return done }
        return false
    }

    /// Ist dieser Termin bereits beendet?
    ///
    /// Ganztägige gelten nie als vorbei — sie betreffen den ganzen Tag, auch
    /// abends noch. Und Aufgaben ebenfalls nicht: Eine überfällige Aufgabe ist
    /// nicht erledigt, sondern das Gegenteil davon. Sie auszublenden, weil ihr
    /// Zeitpunkt vorbei ist, würde genau das Wichtigste verstecken.
    func isOver(at now: Date = Date()) -> Bool {
        guard !isAllDay, !isReminder else { return false }
        guard let end = end ?? start else { return false }
        return end <= now
    }

    /// Anteil der bereits vergangenen Zeit, 0…1. `nil`, wenn der Termin nicht
    /// gerade läuft oder keine Dauer hat.
    func progress(at now: Date = Date()) -> Double? {
        guard !isAllDay, let start, let end, end > start,
              start <= now, end > now else { return nil }
        return (now.timeIntervalSince(start)) / (end.timeIntervalSince(start))
    }

    /// Verbleibende Zeit als „noch 1:45" bzw. „noch 12 Min.".
    func remainingLabel(at now: Date = Date()) -> String? {
        guard let end, end > now, progress(at: now) != nil else { return nil }
        let minutes = Int(end.timeIntervalSince(now) / 60)
        if minutes < 60 { return "noch \(minutes) Min." }
        return "noch \(minutes / 60):\(String(format: "%02d", minutes % 60)) Std."
    }

    /// „in 15 Min." · „in 2:30 Std." — für den Hinweis auf Bevorstehendes.
    func startsInLabel(at now: Date = Date()) -> String? {
        guard let start, start > now else { return nil }
        let minutes = Int(start.timeIntervalSince(now) / 60)
        if minutes < 1 { return "gleich" }
        if minutes < 60 { return "in \(minutes) Min." }
        return "in \(minutes / 60):\(String(format: "%02d", minutes % 60)) Std."
    }

    /// „14:30" · „14:30–15:00" · „ganztägig" · „" (Erinnerung ohne Uhrzeit)
    func timeLabel(using formatter: DateFormatter) -> String {
        if isAllDay { return "ganztägig" }
        guard hasTime, let start else { return "" }
        let from = formatter.string(from: start)
        guard let end, end > start, !isReminder else { return from }
        return "\(from)–\(formatter.string(from: end))"
    }
}
