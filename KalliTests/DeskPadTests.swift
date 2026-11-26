import XCTest

/// Tagesblatt auf dem Schreibtisch (0.14.0): gleiche Gruppen und Reihenfolge wie die
/// Tagesliste, erledigte Aufgaben nach Einstellung, Tagessprung ohne Zeitzonenfehler.
final class DeskPadTests: XCTestCase {

    private let order: [AgendaGroupKind] = [.tasks, .allDay, .timed]

    // MARK: Fenster passt auf den Bildschirm (2026-11-26)

    private let paper = CGSize(width: 388, height: 628)

    func testFitKeepsScaleWhenScreenIsLargeEnough() {
        XCTAssertEqual(DeskPad.fitScale(base: paper, scale: 1.15, available: CGSize(width: 3392, height: 1400)), 1.15)
    }

    func testFitShrinksToSmallScreenHeight() {
        // 504-pt-Bildschirm (gemessen 2026-11-18), abzüglich 16 pt Rand: 488 / 628.
        let fit = DeskPad.fitScale(base: paper, scale: 1, available: CGSize(width: 1296, height: 488))
        XCTAssertEqual(fit, 488.0 / 628.0, accuracy: 0.0001)
        XCTAssertLessThanOrEqual((paper.height * fit).rounded(), 488)
    }

    func testFitNeverGrowsBeyondChosenScale() {
        XCTAssertEqual(DeskPad.fitScale(base: paper, scale: 0.85, available: CGSize(width: 5000, height: 5000)), 0.85)
    }

    func testFitHasLowerBound() {
        XCTAssertEqual(DeskPad.fitScale(base: paper, scale: 1, available: CGSize(width: 100, height: 100)), 0.5)
    }

    private var mixed: [AgendaItem] {
        [
            Fixture.event(id: "t", title: "Zahnarzt", start: Fixture.at(60), end: Fixture.at(120)),
            Fixture.event(id: "a", title: "Urlaub", start: Fixture.now, end: Fixture.at(24 * 60), isAllDay: true),
            Fixture.reminder(id: "r", title: "Milch", due: Fixture.at(30)),
            Fixture.reminder(id: "d", title: "Erledigt", due: Fixture.at(40), completed: true),
        ]
    }

    func testGroupsFollowGivenOrder() {
        let sections = DeskPad.sections(from: mixed, order: order, showCompleted: false)
        XCTAssertEqual(sections.map(\.kind), [.tasks, .allDay, .timed])
        XCTAssertEqual(sections[0].items.map(\.id), ["r"])
        XCTAssertEqual(sections[1].items.map(\.id), ["a"])
        XCTAssertEqual(sections[2].items.map(\.id), ["t"])
    }

    func testReorderedGroupsMoveTogether() {
        let sections = DeskPad.sections(from: mixed, order: [.timed, .tasks, .allDay], showCompleted: false)
        XCTAssertEqual(sections.map(\.kind), [.timed, .tasks, .allDay])
    }

    func testEmptyGroupsAreLeftOut() {
        let onlyEvent = [Fixture.event(start: Fixture.at(60), end: Fixture.at(90))]
        XCTAssertEqual(DeskPad.sections(from: onlyEvent, order: order, showCompleted: false).map(\.kind), [.timed])
        XCTAssertTrue(DeskPad.sections(from: [], order: order, showCompleted: true).isEmpty)
    }

    func testCompletedReminderHiddenUnlessShown() {
        let hidden = DeskPad.sections(from: mixed, order: order, showCompleted: false)
        XCTAssertEqual(hidden.first { $0.kind == .tasks }?.items.map(\.id), ["r"])
        let shown = DeskPad.sections(from: mixed, order: order, showCompleted: true)
        XCTAssertEqual(shown.first { $0.kind == .tasks }?.items.map(\.id), ["r", "d"])
    }

    func testJustCompletedStaysVisibleForTheGraceWindow() {
        let sections = DeskPad.sections(from: mixed, order: order, showCompleted: false, keeping: ["d"])
        XCTAssertEqual(sections.first { $0.kind == .tasks }?.items.map(\.id), ["r", "d"])
    }

    func testIncompleteOrderStillShowsEveryGroup() {
        // Eine ältere Version kann eine unvollständige Reihenfolge gespeichert haben.
        let sections = DeskPad.sections(from: mixed, order: [.timed], showCompleted: false)
        XCTAssertEqual(Set(sections.map(\.kind)), [.timed, .tasks, .allDay])
        XCTAssertEqual(sections.first?.kind, .timed)
    }

    func testShiftedDayLandsOnMidnightAcrossDaylightSavingChange() {
        let cal = Fixture.calendar
        // 25. Oktober 2026: Umstellung auf Winterzeit, der Tag hat 25 Stunden.
        let before = cal.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 15))!
        let next = DeskPad.shifted(before, by: 1, calendar: cal)
        XCTAssertEqual(cal.dateComponents([.year, .month, .day, .hour, .minute], from: next),
                       DateComponents(year: 2026, month: 10, day: 25, hour: 0, minute: 0))
        let after = DeskPad.shifted(next, by: 1, calendar: cal)
        XCTAssertEqual(cal.component(.day, from: after), 26)
        XCTAssertEqual(cal.component(.hour, from: after), 0)
    }

    func testShiftBackwardsMatchesForwardsRoundTrip() {
        let cal = Fixture.calendar
        let start = cal.startOfDay(for: Fixture.now)
        XCTAssertEqual(DeskPad.shifted(DeskPad.shifted(start, by: 5, calendar: cal), by: -5, calendar: cal), start)
    }

    // MARK: - Papierblatt: Blättern

    func testFlipProgressIsSignedAndClamped() {
        XCTAssertEqual(DeskPad.flipProgress(translation: 0, height: 500), 0)
        XCTAssertEqual(DeskPad.flipProgress(translation: -200, height: 500), -0.5, accuracy: 0.0001)
        XCTAssertEqual(DeskPad.flipProgress(translation: -900, height: 500), -1)
        XCTAssertEqual(DeskPad.flipProgress(translation: 900, height: 500), 1)
        XCTAssertEqual(DeskPad.flipProgress(translation: 50, height: 0), 0)
    }

    func testDraggingUpFlipsToNextDayAndDownToPreviousDay() {
        XCTAssertEqual(DeskPad.flipDecision(translation: -200, predicted: -210, height: 500), .next)
        XCTAssertEqual(DeskPad.flipDecision(translation: 200, predicted: 210, height: 500), .previous)
    }

    func testShortSlowDragFallsBack() {
        XCTAssertNil(DeskPad.flipDecision(translation: -60, predicted: -80, height: 500))
        XCTAssertNil(DeskPad.flipDecision(translation: 0, predicted: 0, height: 500))
    }

    func testFastFlickFlipsEvenWhenShort() {
        XCTAssertEqual(DeskPad.flipDecision(translation: -70, predicted: -400, height: 500), .next)
    }

    func testLongDragBeatsOppositeMomentum() {
        // Weit nach unten gezogen, mit schwachem Schwung nach oben losgelassen: Der Schwung gilt nur,
        // wenn er größer ist als der Weg — hier zieht der lange Weg nach unten.
        XCTAssertEqual(DeskPad.flipDecision(translation: 300, predicted: -50, height: 500), .previous)
    }

    // MARK: - Papierblatt: Monatsraster

    private var mondayCalendar: Calendar {
        var cal = Fixture.calendar
        cal.firstWeekday = 2
        return cal
    }

    func testMonthWeeksNovember2026StartingMonday() {
        // 1. November 2026 ist ein Sonntag: sechs leere Felder davor, dann sechs Zeilen.
        let weeks = DeskPad.monthWeeks(for: Fixture.now.addingTimeInterval(54 * 86_400), calendar: mondayCalendar)
        XCTAssertEqual(weeks.count, 6)
        XCTAssertEqual(weeks[0], [nil, nil, nil, nil, nil, nil, 1])
        XCTAssertEqual(weeks[5], [30, nil, nil, nil, nil, nil, nil])
        XCTAssertEqual(weeks.flatMap { $0 }.compactMap { $0 }, Array(1...30))
    }

    func testMonthWeeksStartingSundayShiftsTheFirst() {
        var cal = Fixture.calendar
        cal.firstWeekday = 1
        let weeks = DeskPad.monthWeeks(for: Fixture.now.addingTimeInterval(54 * 86_400), calendar: cal)
        XCTAssertEqual(weeks[0].first, 1)
        XCTAssertEqual(weeks.count, 5)
    }

    func testMonthWeeksSeptember2026HasThirtyDays() {
        let weeks = DeskPad.monthWeeks(for: Fixture.now, calendar: mondayCalendar)
        XCTAssertEqual(weeks.flatMap { $0 }.compactMap { $0 }.count, 30)
        XCTAssertTrue(weeks.allSatisfy { $0.count == 7 })
    }

    func testWeekdayInitialsStartAtFirstWeekdayAndFindSunday() {
        let monday = DeskPad.weekdayInitials(calendar: mondayCalendar)
        XCTAssertEqual(monday.symbols.count, 7)
        XCTAssertEqual(monday.sundayIndex, 6)
        var sunday = Fixture.calendar
        sunday.firstWeekday = 1
        XCTAssertEqual(DeskPad.weekdayInitials(calendar: sunday).sundayIndex, 0)
    }

    // MARK: - Papierblatt: Abreißen

    func testAxisStaysUndecidedUnderTenPoints() {
        XCTAssertNil(DeskPad.dragAxis(CGSize(width: 6, height: 7)))
    }

    func testAxisHorizontalOnlyWhenClearlySideways() {
        XCTAssertEqual(DeskPad.dragAxis(CGSize(width: 30, height: 5)), .horizontal)
        XCTAssertEqual(DeskPad.dragAxis(CGSize(width: -30, height: 5)), .horizontal)
        XCTAssertEqual(DeskPad.dragAxis(CGSize(width: 20, height: 18)), .vertical)  // schräg = blättern
        XCTAssertEqual(DeskPad.dragAxis(CGSize(width: 3, height: -40)), .vertical)
    }

    func testTearProgressIsSignedAndClamped() {
        XCTAssertEqual(DeskPad.tearProgress(translation: 0, width: 300), 0)
        XCTAssertEqual(DeskPad.tearProgress(translation: 67.5, width: 300), 0.5, accuracy: 0.0001)
        XCTAssertEqual(DeskPad.tearProgress(translation: -500, width: 300), -1)
        XCTAssertEqual(DeskPad.tearProgress(translation: 20, width: 0), 0)
    }

    func testTearNeedsDistanceOrMomentum() {
        XCTAssertTrue(DeskPad.tearDecision(translation: 120, predicted: 130, width: 300))
        XCTAssertTrue(DeskPad.tearDecision(translation: -120, predicted: -130, width: 300))
        XCTAssertFalse(DeskPad.tearDecision(translation: 40, predicted: 60, width: 300))
        XCTAssertTrue(DeskPad.tearDecision(translation: 40, predicted: 260, width: 300))
        XCTAssertFalse(DeskPad.tearDecision(translation: 5, predicted: 400, width: 300))  // Zucken
    }
}
