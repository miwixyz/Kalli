import XCTest

/// Tagesblatt auf dem Schreibtisch (0.14.0): gleiche Gruppen und Reihenfolge wie die
/// Tagesliste, erledigte Aufgaben nach Einstellung, Tagessprung ohne Zeitzonenfehler.
final class DeskPadTests: XCTestCase {

    private let order: [AgendaGroupKind] = [.tasks, .allDay, .timed]

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
}
