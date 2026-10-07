import AppKit
import EventKit
import Observation

/// „Die eine Sache" (0.7.0, Michael: „Eine Funktion wie One Thing integrieren").
///
/// Ein frei gesetzter Text — oder eine Erinnerung — als eigener Eintrag in der
/// Menüleiste, neben Kallis Datum. Gesetzt wird er im Kalli-Fenster, per
/// Rechtsklick auf eine Erinnerung oder aus anderen Apps über die Dienste
/// („Als eine Sache in Kalli"). Ist er an eine Erinnerung gebunden,
/// verschwindet er, sobald sie abgehakt oder gelöscht ist — egal ob in Kalli
/// oder in der Erinnerungen-App.
@MainActor
@Observable
final class OneThing {

    /// Längster Text in der Leiste; der volle Text steht im Eingabefeld.
    /// macOS blendet zu breite Leisteneinträge ohne Hinweis aus.
    nonisolated static let barMaxChars = 40
    /// Obergrenze für gespeicherten Text (Dienste können ganze Absätze liefern).
    nonisolated static let maxChars = 200

    private enum Key {
        static let text = "oneThingText"
        static let reminderID = "oneThingReminderID"
    }

    private(set) var text: String
    /// `calendarItemIdentifier` der Erinnerung, falls die Sache eine ist.
    private(set) var reminderID: String?

    var isSet: Bool { !text.isEmpty }
    var barText: String { Self.barText(text) }

    private let defaults: UserDefaults
    /// Liefert den aktuellen Stand einer Erinnerung.
    private let lookup: @MainActor (String) -> ReminderLookup
    private var observer: NSObjectProtocol?

    struct ReminderState: Equatable, Sendable {
        let title: String
        let isCompleted: Bool
    }

    /// `unknown` = nicht prüfbar (keine Erinnerungs-Berechtigung). Dann bleibt die
    /// Sache stehen: Ohne Berechtigung liefert EventKit `nil`, und das hieße
    /// sonst „gelöscht" — die Sache verschwände beim Entzug der Berechtigung still.
    enum ReminderLookup: Equatable, Sendable { case unknown, gone, found(ReminderState) }

    init(defaults: UserDefaults = .standard, lookup: @escaping @MainActor (String) -> ReminderLookup) {
        self.defaults = defaults
        self.lookup = lookup
        text = defaults.string(forKey: Key.text) ?? ""
        reminderID = defaults.string(forKey: Key.reminderID)
        reconcile()
        // Abgehakt oder umbenannt — in Kalli oder der Erinnerungen-App: EventKit
        // meldet jede Änderung. `object: nil`, weil die Meldung von Kallis
        // eigenem EKEventStore im CalendarStore kommt.
        observer = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.reconcile() }
        }
    }

    // Kein deinit — lebt so lange wie die App (gleiche Begründung wie MenuBarLabel).

    /// Freier Text. Leer = Sache entfernen.
    func set(text newValue: String) {
        store(text: Self.clean(newValue), reminderID: nil)
    }

    /// Eine Erinnerung als Sache. Verschwindet mit dem Abhaken.
    func set(reminderID id: String, title: String) {
        store(text: Self.clean(title), reminderID: id)
    }

    func clear() { store(text: "", reminderID: nil) }

    /// Gleicht eine gebundene Erinnerung mit EventKit ab.
    func reconcile() {
        guard let id = reminderID else { return }
        switch Self.outcome(of: lookup(id), currentText: text) {
        case .keep: break
        case .clear: clear()
        case .rename(let title): store(text: title, reminderID: id)
        }
    }

    private func store(text newText: String, reminderID newID: String?) {
        text = newText
        reminderID = newText.isEmpty ? nil : newID
        defaults.set(text, forKey: Key.text)
        if let reminderID { defaults.set(reminderID, forKey: Key.reminderID) } else { defaults.removeObject(forKey: Key.reminderID) }
    }

    // MARK: - Reine Logik (getestet in OneThingTests)

    enum Outcome: Equatable { case keep, clear, rename(String) }

    nonisolated static func outcome(of lookup: ReminderLookup, currentText: String) -> Outcome {
        let state: ReminderState
        switch lookup {
        case .unknown: return .keep
        case .gone: return .clear
        case .found(let found): state = found
        }
        if state.isCompleted { return .clear }
        let title = clean(state.title)
        if title.isEmpty { return .clear }
        return title == currentText ? .keep : .rename(title)
    }

    /// Eine Zeile: Zeilenumbrüche und Tabs werden zu Leerzeichen, Leerraum
    /// zusammengefasst, höchstens `maxChars` Zeichen.
    nonisolated static func clean(_ raw: String) -> String {
        let oneLine = raw.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return String(oneLine.prefix(maxChars))
    }

    nonisolated static func barText(_ text: String) -> String {
        text.count <= barMaxChars ? text : String(text.prefix(barMaxChars - 1)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

/// „Als eine Sache in Kalli" im Dienste-Menü anderer Apps (Info.plist `NSServices`).
@MainActor
final class OneThingService: NSObject {
    private let oneThing: OneThing
    init(oneThing: OneThing) { self.oneThing = oneThing }

    @objc func setOneThing(_ pasteboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let raw = pasteboard.string(forType: .string), !OneThing.clean(raw).isEmpty else {
            error.pointee = "Kein Text ausgewählt." as NSString
            return
        }
        oneThing.set(text: raw)
    }
}
