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

    /// „14:30" · „14:30–15:00" · „ganztägig" · „" (Erinnerung ohne Uhrzeit)
    func timeLabel(using formatter: DateFormatter) -> String {
        if isAllDay { return "ganztägig" }
        guard hasTime, let start else { return "" }
        let from = formatter.string(from: start)
        guard let end, end > start, !isReminder else { return from }
        return "\(from)–\(formatter.string(from: end))"
    }
}
