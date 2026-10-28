import XCTest

/// Neue Erinnerung (0.10.0): Texterkennung, Knöpfe, Felder für EventKit, Vollbild für „Dringend".
/// `Fixture.now` = Dienstag, 22.09.2026, 12:00 (Berlin).
final class QuickReminderTests: XCTestCase {

    private let cal = Fixture.calendar
    private let now = Fixture.now

    private func day(_ d: Int, _ m: Int = 9, _ y: Int = 2026) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    private func parse(_ s: String) -> QuickReminder.Parsed {
        QuickReminder.parse(s, now: now, calendar: cal)
    }

    // MARK: Texterkennung

    func testTomorrowWithHour() {
        let p = parse("Zahnarzt anrufen morgen 15 Uhr")
        XCTAssertEqual(p.title, "Zahnarzt anrufen")
        XCTAssertEqual(p.day, day(23))
        XCTAssertEqual(p.time, .init(hour: 15, minute: 0))
    }

    func testDayAfterTomorrowIsNotTomorrow() {
        XCTAssertEqual(parse("übermorgen Müll").day, day(24))
        XCTAssertEqual(parse("übermorgen Müll").title, "Müll")
    }

    func testTodayAndClockFormats() {
        XCTAssertEqual(parse("heute 9:30 Rückruf").time, .init(hour: 9, minute: 30))
        XCTAssertEqual(parse("Rückruf um 18.45 Uhr").time, .init(hour: 18, minute: 45))
        XCTAssertEqual(parse("Rückruf um 7").time, .init(hour: 7, minute: 0))
        XCTAssertEqual(parse("Rückruf um 7").title, "Rückruf")
        XCTAssertEqual(parse("heute Rückruf").day, day(22))
    }

    func testWeekdayIsNextOccurrenceNeverToday() {
        // Heute ist Dienstag: „Dienstag" meint den nächsten, nicht heute.
        XCTAssertEqual(parse("am Dienstag Training").day, day(29))
        XCTAssertEqual(parse("Freitag Steuer").day, day(25))
        XCTAssertEqual(parse("nächsten Montag Bank").day, day(28))
        XCTAssertEqual(parse("nächsten Montag Bank").title, "Bank")
    }

    func testNextWeekIsMonday() {
        XCTAssertEqual(parse("nächste Woche Angebot").day, day(28))
        XCTAssertEqual(QuickReminder.day(.nextWeek, now: now, calendar: cal), day(28))
    }

    func testDateWithAndWithoutYear() {
        XCTAssertEqual(parse("Geburtstag 24.10.").day, day(24, 10))
        XCTAssertEqual(parse("Geburtstag 24.10.").title, "Geburtstag")
        // Schon vorbei → nächstes Jahr.
        XCTAssertEqual(parse("Steuer 1.3.").day, day(1, 3, 2027))
        XCTAssertEqual(parse("Termin 5.1.27").day, day(5, 1, 2027))
        XCTAssertNil(parse("Termin 31.2.").day)
    }

    func testDateIsNotReadAsTime() {
        let p = parse("Abgabe 24.10. 15 Uhr")
        XCTAssertEqual(p.day, day(24, 10))
        XCTAssertEqual(p.time, .init(hour: 15, minute: 0))
        XCTAssertEqual(p.title, "Abgabe")
    }

    func testOnlyWholeWords() {
        let p = parse("Morgenkreis vorbereiten")
        XCTAssertNil(p.day)
        XCTAssertEqual(p.title, "Morgenkreis vorbereiten")
    }

    func testInvalidTimeStaysInTitle() {
        let p = parse("Lauf 25 Uhr")
        XCTAssertNil(p.time)
        XCTAssertEqual(p.title, "Lauf 25 Uhr")
    }

    func testNothingRecognized() {
        XCTAssertEqual(parse("Milch kaufen"), .init(title: "Milch kaufen", day: nil, time: nil))
    }

    // MARK: Felder für EventKit

    func testFieldsWithTimeHaveAlarmAndUrgentPriority() throws {
        let draft = QuickReminder.Draft(title: "  Rückruf  ", day: day(23),
                                        time: .init(hour: 15, minute: 5), urgent: true)
        let f = try XCTUnwrap(QuickReminder.fields(for: draft, calendar: cal))
        XCTAssertEqual(f.title, "Rückruf")
        XCTAssertEqual(f.priority, 1)
        XCTAssertTrue(QuickReminder.isHighPriority(f.priority))
        XCTAssertEqual(f.due.day, 23)
        XCTAssertEqual(f.due.hour, 15)
        XCTAssertEqual(f.due.minute, 5)
        XCTAssertEqual(f.alarmDate, cal.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 15, minute: 5)))
    }

    func testFieldsWithoutTimeHaveNoHourAndNoAlarm() throws {
        let draft = QuickReminder.Draft(title: "Milch", day: day(23), time: nil, urgent: false)
        let f = try XCTUnwrap(QuickReminder.fields(for: draft, calendar: cal))
        XCTAssertNil(f.due.hour)
        XCTAssertNil(f.alarmDate)
        XCTAssertEqual(f.priority, 0)
    }

    func testEmptyTitleIsRejected() {
        XCTAssertNil(QuickReminder.fields(for: .init(title: "   ", day: day(23), time: nil, urgent: false),
                                          calendar: cal))
    }

    func testPriorityMapping() {
        XCTAssertFalse(QuickReminder.isHighPriority(0))
        XCTAssertTrue(QuickReminder.isHighPriority(4))
        XCTAssertFalse(QuickReminder.isHighPriority(5))
    }

    // MARK: Vollbild für dringende Erinnerungen

    private func urgent(due: Date, hasTime: Bool = true, completed: Bool = false) -> AgendaItem {
        var r = Fixture.reminder(due: due, hasTime: hasTime, completed: completed)
        r.isUrgent = true
        return r
    }

    func testUrgentReminderFiresAtDueTimeWithoutLead() {
        let r = urgent(due: Fixture.at(0.5))
        // 30 s vor Fälligkeit: Termine mit 1 Min. Vorlauf wären fällig, die Erinnerung noch nicht.
        XCTAssertTrue(FullScreenAlerts.due(in: [r], now: now, lead: 60, shown: []).isEmpty)
        XCTAssertEqual(FullScreenAlerts.upcoming(in: [r], now: now, lead: 60).count, 1)
        XCTAssertEqual(FullScreenAlerts.due(in: [r], now: Fixture.at(0.5), lead: 60, shown: []).count, 1)
        XCTAssertEqual(FullScreenAlerts.alertDate(r, lead: 60), Fixture.at(0.5))
    }

    func testOnlyOpenUrgentRemindersWithTime() {
        XCTAssertTrue(FullScreenAlerts.isEligible(urgent(due: now)))
        XCTAssertFalse(FullScreenAlerts.isEligible(urgent(due: now, hasTime: false)))
        XCTAssertFalse(FullScreenAlerts.isEligible(urgent(due: now, completed: true)))
        XCTAssertFalse(FullScreenAlerts.isEligible(Fixture.reminder(due: now)))
    }

    func testUrgentReminderIsNotSnoozable() {
        XCTAssertTrue(FullScreenAlerts.snoozable([urgent(due: now)], now: now).isEmpty)
    }

    func testStatusLabelForReminder() {
        XCTAssertEqual(FullScreenAlertView.status(start: now, now: now, isReminder: true),
                       "Dringend · jetzt fällig")
        XCTAssertEqual(FullScreenAlertView.status(start: Fixture.at(-3), now: now, isReminder: true),
                       "Dringend · seit 3 Min. fällig")
    }

    // MARK: Reihenfolge der Tagesliste

    func testOrderDefaultsToTasksFirst() {
        XCTAssertEqual(AgendaGroupKind.normalized([]), [.tasks, .allDay, .timed])
    }

    func testOrderRepairsDuplicatesAndMissing() {
        XCTAssertEqual(AgendaGroupKind.normalized([.timed, .timed]), [.timed, .tasks, .allDay])
    }

    func testMoveStaysInBounds() {
        let order: [AgendaGroupKind] = [.tasks, .allDay, .timed]
        XCTAssertEqual(AgendaGroupKind.moved(.allDay, by: -1, in: order), [.allDay, .tasks, .timed])
        XCTAssertEqual(AgendaGroupKind.moved(.tasks, by: -1, in: order), order)
        XCTAssertEqual(AgendaGroupKind.moved(.timed, by: 1, in: order), order)
    }
}
