import Foundation
import Observation

/// Einstellungen. Bewusst schmal — was hier landet, muss jemand pflegen.
@MainActor
@Observable
final class Preferences {

    private enum Key {
        static let hidden = "hiddenSourceIDs"
        static let showIcon = "showIconInMenuBar"
        static let showDate = "showDateInMenuBar"
        static let showNextEvent = "showNextEventInMenuBar"
        static let nextEventWidth = "nextEventMaxChars"
        static let dateFormat = "menuBarDateFormat"
        static let showWeekNumbers = "showWeekNumbers"
        static let showCompleted = "showCompletedReminders"
        static let showProgress = "showRunningProgress"
        static let showUpcoming = "showUpcomingBanner"
        static let upcomingLead = "upcomingLeadMinutes"
    }

    private let defaults: UserDefaults

    /// IDs ausgeblendeter Kalender und Erinnerungslisten.
    var hiddenSourceIDs: Set<String> {
        didSet { defaults.set(Array(hiddenSourceIDs), forKey: Key.hidden) }
    }

    /// Kalenderblatt-Symbol in der Leiste. Neben dem Datumstext ist es
    /// redundant — die Zahl steht dann zweimal da.
    var showIconInMenuBar: Bool {
        didSet { defaults.set(showIconInMenuBar, forKey: Key.showIcon) }
    }

    /// Datumstext neben dem Symbol. Aus = nur das Kalenderblatt mit der Tageszahl,
    /// das schmalste sinnvolle Erscheinungsbild.
    var showDateInMenuBar: Bool {
        didSet { defaults.set(showDateInMenuBar, forKey: Key.showDate) }
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

    /// Fortschritt des laufenden Termins — in der Leiste und im Popover.
    var showRunningProgress: Bool {
        didSet { defaults.set(showRunningProgress, forKey: Key.showProgress) }
    }

    /// Auffälliger Hinweis auf den nächsten Termin, oben im Popover.
    var showUpcomingBanner: Bool {
        didSet { defaults.set(showUpcomingBanner, forKey: Key.showUpcoming) }
    }

    /// Wie lange vorher der Hinweis erscheint.
    var upcomingLeadMinutes: Int {
        didSet { defaults.set(upcomingLeadMinutes, forKey: Key.upcomingLead) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hiddenSourceIDs = Set(defaults.stringArray(forKey: Key.hidden) ?? [])
        showIconInMenuBar = defaults.object(forKey: Key.showIcon) as? Bool ?? false
        showDateInMenuBar = defaults.object(forKey: Key.showDate) as? Bool ?? true
        showNextEventInMenuBar = defaults.object(forKey: Key.showNextEvent) as? Bool ?? true
        nextEventMaxChars = defaults.object(forKey: Key.nextEventWidth) as? Int ?? 22
        menuBarDateFormat = defaults.string(forKey: Key.dateFormat) ?? "EEE d. MMM"
        showWeekNumbers = defaults.object(forKey: Key.showWeekNumbers) as? Bool ?? true
        showCompletedReminders = defaults.object(forKey: Key.showCompleted) as? Bool ?? false
        showRunningProgress = defaults.object(forKey: Key.showProgress) as? Bool ?? true
        showUpcomingBanner = defaults.object(forKey: Key.showUpcoming) as? Bool ?? true
        upcomingLeadMinutes = defaults.object(forKey: Key.upcomingLead) as? Int ?? 60
    }

    /// Ohne Symbol UND ohne Datum wäre der Eintrag leer — und damit unsichtbar.
    /// Die App liefe weiter, wäre aber nicht mehr auffindbar. Genau das ist am
    /// 2026-09-21 passiert, bevor es das Symbol gab.
    var menuBarWouldBeEmpty: Bool { !showIconInMenuBar && !showDateInMenuBar }

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
