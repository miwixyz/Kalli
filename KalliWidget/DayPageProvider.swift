import EventKit
import OSLog
import WidgetKit

private let log = Logger(subsystem: "com.kalli.app", category: "widget")

/// Ein Stand des Kalenderblatts: Tag und die Einträge dieses Tages.
struct DayPageEntry: TimelineEntry {
    let date: Date
    let items: [AgendaItem]
    /// `false`, wenn Kalli (noch) keinen Kalenderzugriff hat — das Widget sagt es dann.
    let hasAccess: Bool

    static func sample(_ date: Date) -> DayPageEntry {
        let start = Calendar.current.startOfDay(for: date)
        func item(_ id: String, _ title: String, _ hour: Double, _ kind: AgendaItem.Kind = .event) -> AgendaItem {
            AgendaItem(id: id, title: title, start: start.addingTimeInterval(hour * 3600),
                       end: start.addingTimeInterval((hour + 1) * 3600), isAllDay: false, hasTime: true,
                       kind: kind, sourceID: "", color: RGBA(r: 0.24, g: 0.30, b: 0.60, a: 1), hasAlarms: false)
        }
        return DayPageEntry(date: date, items: [
            item("a", "Team-Runde", 9),
            item("b", "Mittagessen", 12.5),
            item("c", "Unterlagen schicken", 15, .reminder(completed: false)),
        ], hasAccess: true)
    }
}

/// Liest Termine und Erinnerungen des Tages direkt aus EventKit — lesend, im Widget-Prozess.
/// Neu geladen wird alle 15 Minuten, um Mitternacht und wenn Kalli eine Kalenderänderung meldet
/// (`WidgetCenter.reloadTimelines` in `CalendarStore`).
struct DayPageProvider: TimelineProvider {

    func placeholder(in context: Context) -> DayPageEntry { .sample(Date()) }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (DayPageEntry) -> Void) {
        if context.isPreview { return completion(.sample(Date())) }
        Task { completion(await Self.load(at: Date())) }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<DayPageEntry>) -> Void) {
        Task {
            let now = Date()
            let loaded = await Self.load(at: now)
            let calendar = Calendar.current
            let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
                ?? now.addingTimeInterval(3600)
            // Wie Punkti: ein Eintrag alle 5 Minuten für die nächste Stunde, damit „LÄUFT“ und
            // „IN 20 MIN“ stimmen; danach (spätestens um Mitternacht) neu lesen.
            let horizon = min(midnight, now.addingTimeInterval(3600))
            let entries = stride(from: 0.0, to: horizon.timeIntervalSince(now), by: 300).map {
                DayPageEntry(date: now.addingTimeInterval($0), items: loaded.items, hasAccess: loaded.hasAccess)
            }
            completion(Timeline(entries: entries.isEmpty ? [loaded] : entries, policy: .after(horizon)))
        }
    }

    static func load(at now: Date) async -> DayPageEntry {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
            return DayPageEntry(date: now, items: [], hasAccess: false)
        }
        let store = EKEventStore()
        let eventStatus = EKEventStore.authorizationStatus(for: .event)
        let reminderStatus = EKEventStore.authorizationStatus(for: .reminder)
        // Messpunkt: „Kalli hat Zugriff“ und „das Widget hat Zugriff“ sind zwei Aussagen.
        log.notice("Zugriff Kalender \(eventStatus.rawValue, privacy: .public), Erinnerungen \(reminderStatus.rawValue, privacy: .public)")
        let events = eventStatus == .fullAccess
        let reminders = reminderStatus == .fullAccess
        var items: [AgendaItem] = []
        if events {
            let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
            items += store.events(matching: predicate)
                .filter { $0.status != .canceled && !isDeclined($0) }
                .map(mapEvent)
        }
        if reminders {
            items += await openReminders(in: store, dueBefore: end, dayStart: start)
        }
        items.sort { ($0.start ?? .distantPast) < ($1.start ?? .distantPast) }
        return DayPageEntry(date: now, items: items, hasAccess: events || reminders)
    }

    private static func isDeclined(_ event: EKEvent) -> Bool {
        event.attendees?.contains { $0.isCurrentUser && $0.participantStatus == .declined } ?? false
    }

    private static func color(_ calendar: EKCalendar?) -> RGBA {
        guard let comps = calendar?.cgColor?.components, comps.count >= 3 else { return .fallback }
        return RGBA(r: Double(comps[0]), g: Double(comps[1]), b: Double(comps[2]), a: 1)
    }

    private static func mapEvent(_ event: EKEvent) -> AgendaItem {
        AgendaItem(id: "\(event.eventIdentifier ?? UUID().uuidString)-\(event.startDate.timeIntervalSince1970)",
                   title: event.title ?? "", start: event.startDate, end: event.endDate,
                   isAllDay: event.isAllDay, hasTime: !event.isAllDay, kind: .event,
                   sourceID: event.calendar?.calendarIdentifier ?? "", color: color(event.calendar),
                   hasAlarms: false)
    }

    /// Offene Erinnerungen, die heute fällig sind. Überfällige vom Vortag zeigt das Tagesblatt in
    /// Kalli auch nicht; das Widget hält es gleich.
    private static func openReminders(in store: EKEventStore, dueBefore end: Date, dayStart: Date) async -> [AgendaItem] {
        let predicate = store.predicateForIncompleteReminders(withDueDateStarting: dayStart, ending: end, calendars: nil)
        let found: [(String, String, Date?, Bool, RGBA, String)] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { reminders in
                let rows = (reminders ?? []).map { reminder in
                    let comps = reminder.dueDateComponents
                    let due = comps.flatMap { Calendar.current.date(from: $0) }
                    let hasTime = comps?.hour != nil
                    return (reminder.calendarItemIdentifier, reminder.title ?? "", due, hasTime,
                            color(reminder.calendar), reminder.calendar?.calendarIdentifier ?? "")
                }
                continuation.resume(returning: rows)
            }
        }
        return found.map { id, title, due, hasTime, color, source in
            AgendaItem(id: id, title: title, start: due, end: nil, isAllDay: false, hasTime: hasTime,
                       kind: .reminder(completed: false), sourceID: source, color: color, hasAlarms: false)
        }
    }
}
