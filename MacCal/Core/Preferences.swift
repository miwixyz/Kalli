import Foundation
import Observation

/// Einstellungen. Bewusst schmal — was hier landet, muss jemand pflegen.
@MainActor
@Observable
final class Preferences {

    private enum Key {
        static let hidden = "hiddenSourceIDs"
        static let showNextEvent = "showNextEventInMenuBar"
        static let nextEventWidth = "nextEventMaxChars"
        static let dateFormat = "menuBarDateFormat"
        static let showWeekNumbers = "showWeekNumbers"
        static let showCompleted = "showCompletedReminders"
    }

    private let defaults: UserDefaults

    /// IDs ausgeblendeter Kalender und Erinnerungslisten.
    var hiddenSourceIDs: Set<String> {
        didSet { defaults.set(Array(hiddenSourceIDs), forKey: Key.hidden) }
    }

    var showNextEventInMenuBar: Bool {
        didSet { defaults.set(showNextEventInMenuBar, forKey: Key.showNextEvent) }
    }

    /// Ab wie vielen Zeichen der Titel des nächsten Termins gekürzt wird.
    /// Ohne Deckel springt die Breite der Menüleiste bei jedem Terminwechsel.
    var nextEventMaxChars: Int {
        didSet { defaults.set(nextEventMaxChars, forKey: Key.nextEventWidth) }
    }

    var menuBarDateFormat: String {
        didSet { defaults.set(menuBarDateFormat, forKey: Key.dateFormat) }
    }

    var showWeekNumbers: Bool {
        didSet { defaults.set(showWeekNumbers, forKey: Key.showWeekNumbers) }
    }

    var showCompletedReminders: Bool {
        didSet { defaults.set(showCompletedReminders, forKey: Key.showCompleted) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hiddenSourceIDs = Set(defaults.stringArray(forKey: Key.hidden) ?? [])
        showNextEventInMenuBar = defaults.object(forKey: Key.showNextEvent) as? Bool ?? true
        nextEventMaxChars = defaults.object(forKey: Key.nextEventWidth) as? Int ?? 22
        menuBarDateFormat = defaults.string(forKey: Key.dateFormat) ?? "EEE d. MMM"
        showWeekNumbers = defaults.object(forKey: Key.showWeekNumbers) as? Bool ?? true
        showCompletedReminders = defaults.object(forKey: Key.showCompleted) as? Bool ?? false
    }

    func isHidden(_ id: String) -> Bool { hiddenSourceIDs.contains(id) }

    func setHidden(_ hidden: Bool, for id: String) {
        if hidden { hiddenSourceIDs.insert(id) } else { hiddenSourceIDs.remove(id) }
    }

    /// Entfernt IDs von Kalendern, die es nicht mehr gibt.
    ///
    /// Ohne das wächst die Liste still weiter: Ein gelöschter Google-Kalender
    /// bliebe für immer als ausgeblendet vermerkt, und käme er je zurück, wäre
    /// er unsichtbar, ohne dass jemand weiß warum.
    func pruneHidden(to existing: Set<String>) {
        let cleaned = hiddenSourceIDs.intersection(existing)
        if cleaned != hiddenSourceIDs { hiddenSourceIDs = cleaned }
    }
}
