import XCTest
@testable import Kalli

/// Deckt ab, **welche** Termine eine Systemmitteilung bekommen.
///
/// Die Regeln kommen aus zwei Entscheidungen und einem Audit-Fund:
///
/// - **Kein Doppel-Alarm** (mit Michael entschieden, 2026-09-22): Trägt ein
///   Termin im Kalender schon einen Alarm, meldet Apple Kalender selbst. Zwei
///   Klingeln für denselben Termin sind kein doppelter Hinweis, sondern einer,
///   dem man nicht mehr glaubt.
/// - **Serientermine brauchen je Vorkommen eine eigene Kennung** (Audit-Fund
///   🟡): `eventIdentifier` ist laut EventKit-Vertrag für alle Vorkommen
///   identisch. Mit ihr allein ersetzte jede geplante Mitteilung die vorige —
///   bei „alle 4 Stunden" blieb genau eine übrig.
final class AlertCandidateTests: XCTestCase {

    private let now = Fixture.now
    private let lead: TimeInterval = 10 * 60

    func testIncludesPlainUpcomingEvent() {
        let soon = Fixture.event(title: "Zahnarzt", start: Fixture.at(30), end: Fixture.at(60))

        let result = EventAlerts.candidates(in: [soon], now: now, lead: lead)

        XCTAssertEqual(result.map(\.title), ["Zahnarzt"])
    }

    /// Der Vorsatz „kein Doppel-Alarm" in Testform.
    func testExcludesEventWithOwnCalendarAlarm() {
        let armed = Fixture.event(title: "hat Alarm", start: Fixture.at(30),
                                  end: Fixture.at(60), hasAlarms: true)

        XCTAssertTrue(EventAlerts.candidates(in: [armed], now: now, lead: lead).isEmpty)
    }

    func testExcludesAllDayEvents() {
        let allDay = Fixture.event(title: "Feiertag", start: Fixture.at(30),
                                   end: Fixture.at(600), isAllDay: true)

        XCTAssertTrue(EventAlerts.candidates(in: [allDay], now: now, lead: lead).isEmpty)
    }

    func testExcludesReminders() {
        let task = Fixture.reminder(title: "Aufgabe", due: Fixture.at(30))

        XCTAssertTrue(EventAlerts.candidates(in: [task], now: now, lead: lead).isEmpty)
    }

    /// Eine Mitteilung mit Auslöser in der Vergangenheit erscheint nie. Sie
    /// trotzdem zu planen hieße, Erfolg zu melden, ohne zu wirken.
    func testExcludesEventWhoseLeadWindowAlreadyPassed() {
        let tooClose = Fixture.event(title: "in 5 Min.", start: Fixture.at(5), end: Fixture.at(35))

        XCTAssertTrue(EventAlerts.candidates(in: [tooClose], now: now, lead: lead).isEmpty)
    }

    /// Genau auf der Vorlaufgrenze: Der Auslöser wäre *jetzt*, also nicht mehr
    /// in der Zukunft — ausgeschlossen. Die Grenze wird festgeschrieben, damit
    /// eine spätere Änderung sie nicht unbemerkt verschiebt.
    func testExcludesEventExactlyAtLeadBoundary() {
        let boundary = Fixture.event(title: "in genau 10 Min.",
                                     start: Fixture.at(10), end: Fixture.at(40))

        XCTAssertTrue(EventAlerts.candidates(in: [boundary], now: now, lead: lead).isEmpty)
    }

    func testExcludesEventAlreadyRunning() {
        let running = Fixture.event(title: "läuft", start: Fixture.at(-10), end: Fixture.at(50))

        XCTAssertTrue(EventAlerts.candidates(in: [running], now: now, lead: lead).isEmpty)
    }

    /// Der Audit-Fund 🟡 in Testform: Zwei Vorkommen derselben Serie müssen
    /// **beide** eine Mitteilung bekommen — und dafür verschiedene Kennungen
    /// haben. Mit der nackten `eventIdentifier` wären beide gleich benannt, und
    /// die zweite hätte die erste ersetzt.
    func testRecurringOccurrencesYieldDistinctCandidates() {
        let base = "SERIEN-ID"
        let first = Fixture.event(
            id: CalendarStore.eventID(base: base, start: Fixture.at(30)),
            title: "Medikament", start: Fixture.at(30), end: Fixture.at(35)
        )
        let second = Fixture.event(
            id: CalendarStore.eventID(base: base, start: Fixture.at(270)),
            title: "Medikament", start: Fixture.at(270), end: Fixture.at(275)
        )

        let result = EventAlerts.candidates(in: [first, second], now: now, lead: lead)

        XCTAssertEqual(result.count, 2, "beide Vorkommen müssen eine Mitteilung bekommen")
        XCTAssertEqual(Set(result.map(\.id)).count, 2,
                       "gleiche Kennung hieße: die zweite Mitteilung ersetzt die erste")
    }

    func testEmptyHorizonYieldsNothing() {
        XCTAssertTrue(EventAlerts.candidates(in: [], now: now, lead: lead).isEmpty)
    }
}
