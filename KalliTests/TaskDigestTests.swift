import XCTest

/// Aufgaben-Pop-up (`TaskDigest`): welche Aufgaben, wann es kommt, wann Schlummern gilt.
///
/// Entscheidungen (Michael, 2026-11-17): einmal täglich zur eingestellten Stunde, nur heute
/// fällige offene Erinnerungen, Schlummern um eine Stunde, „Schließen" gilt für den ganzen Tag.
final class TaskDigestTests: XCTestCase {

    private let now = Fixture.now            // Dienstag, 22.09.2026, 12:00
    private let calendar = Fixture.calendar

    private func today(_ hour: Int, _ minute: Int = 0, dayOffset: Int = 0) -> Date {
        let day = calendar.date(byAdding: .day, value: dayOffset, to: calendar.startOfDay(for: now))!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
    }

    private func fire(now: Date? = nil, hour: Int = 9, handled: Date? = nil, snooze: Date? = nil) -> Date? {
        TaskDigest.nextFire(now: now ?? self.now, hour: hour, handledDay: handled,
                            snoozeUntil: snooze, calendar: calendar)
    }

    // MARK: Position (Michael, 2026-11-18: oben rechts liegen die Mitteilungen von macOS)

    private let size = NSSize(width: 340, height: 120)
    private let main = NSRect(x: 0, y: 0, width: 1920, height: 1050)
    private let second = NSRect(x: 1920, y: 0, width: 1920, height: 1080)

    func testWithoutSavedPositionItSitsTopLeftOfTheMainScreen() {
        let corner = TaskDigestPresenter.topLeft(saved: nil, size: size, areas: [main, second])
        XCTAssertEqual(corner, NSPoint(x: 16, y: 1038))
    }

    func testSavedPositionIsKept() {
        let saved = NSPoint(x: 2400, y: 700)
        XCTAssertEqual(TaskDigestPresenter.topLeft(saved: saved, size: size, areas: [main, second]), saved)
    }

    func testSavedPositionOnAMissingScreenFallsBackToTopLeft() {
        let saved = NSPoint(x: 2400, y: 700)
        XCTAssertEqual(TaskDigestPresenter.topLeft(saved: saved, size: size, areas: [main]),
                       NSPoint(x: 16, y: 1038))
    }

    func testSavedPositionThatNoLongerFitsFallsBackToTopLeft() {
        let saved = NSPoint(x: 1700, y: 700)   // ragt rechts über den Rand
        XCTAssertEqual(TaskDigestPresenter.topLeft(saved: saved, size: size, areas: [main]),
                       NSPoint(x: 16, y: 1038))
    }

    // MARK: Auswahl

    func testOnlyOpenRemindersAreListed() {
        let open = Fixture.reminder(id: "offen", due: Fixture.at(60))
        let done = Fixture.reminder(id: "erledigt", due: Fixture.at(60), completed: true)
        let event = Fixture.event(start: Fixture.at(60), end: Fixture.at(90))
        XCTAssertEqual(TaskDigest.openTasks(in: [done, event, open]).map(\.id), ["offen"])
    }

    func testOrderIsUrgentThenTimedThenUntimed() {
        let untimed = Fixture.reminder(id: "ohne", due: calendar.startOfDay(for: now), hasTime: false)
        let late = Fixture.reminder(id: "spaet", due: Fixture.at(120))
        let early = Fixture.reminder(id: "frueh", due: Fixture.at(-60))
        var urgent = Fixture.reminder(id: "dringend", due: Fixture.at(300))
        urgent.isUrgent = true
        XCTAssertEqual(TaskDigest.openTasks(in: [untimed, late, urgent, early]).map(\.id),
                       ["dringend", "frueh", "spaet", "ohne"])
    }

    // MARK: Zeitpunkt

    func testBeforeTheHourItWaitsForTodaysHour() {
        XCTAssertEqual(fire(now: today(7, 30)), today(9))
    }

    func testAfterTheHourItIsDueNow() {
        // Mac war um 9 Uhr aus: Der Zeitpunkt liegt in der Vergangenheit, also jetzt zeigen.
        let at = fire()
        XCTAssertEqual(at, today(9))
        XCTAssertLessThanOrEqual(at!, now)
    }

    func testHandledTodayMovesToTomorrow() {
        XCTAssertEqual(fire(handled: today(9, 5)), today(9, dayOffset: 1))
    }

    func testHandledYesterdayDoesNotBlockToday() {
        XCTAssertEqual(fire(now: today(7), handled: today(9, 5, dayOffset: -1)), today(9))
    }

    func testSnoozeFromTodayWins() {
        XCTAssertEqual(fire(snooze: today(12, 40)), today(12, 40))
    }

    func testSnoozeAlreadyReachedIsDueNow() {
        // Mac schlief über den Schlummer-Zeitpunkt hinweg: beim Aufwachen am selben Tag zeigen.
        XCTAssertEqual(fire(now: today(15), snooze: today(11)), today(11))
    }

    func testSnoozeFromYesterdayIsDropped() {
        XCTAssertEqual(fire(now: today(7), snooze: today(18, dayOffset: -1)), today(9))
    }

    // MARK: Schlummern

    func testSnoozeIsOneHour() {
        XCTAssertEqual(TaskDigest.snoozeDate(now: now, calendar: calendar), now.addingTimeInterval(3600))
    }

    func testNoSnoozeAcrossMidnight() {
        XCTAssertNil(TaskDigest.snoozeDate(now: today(23, 30), calendar: calendar))
        XCTAssertNotNil(TaskDigest.snoozeDate(now: today(22, 59), calendar: calendar))
    }
}
