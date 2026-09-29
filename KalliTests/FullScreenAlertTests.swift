import XCTest
@testable import Kalli

/// Vollbild-Hinweis: welche Termine, wann, und welcher Link geöffnet werden darf.
///
/// Entscheidungen mit Michael (2026-09-29): alle Termine mit Uhrzeit, **auch mit
/// eigenem Alarm**; nicht ganztägig, nicht abgelehnt; nur http/https-Links.
final class FullScreenAlertTests: XCTestCase {

    private let now = Fixture.now
    private let lead: TimeInterval = 60

    // MARK: Auswahl

    func testIncludesEventWithOwnCalendarAlarm() {
        // Anders als bei der Mitteilung: Der Vollbild-Hinweis ist ein eigener Kanal.
        let item = Fixture.event(start: Fixture.at(0.5), end: Fixture.at(30), hasAlarms: true)
        XCTAssertEqual(FullScreenAlerts.due(in: [item], now: now, lead: lead, shown: []).count, 1)
    }

    func testExcludesAllDayDeclinedAndReminders() {
        let allDay = Fixture.event(start: Fixture.at(0.5), end: Fixture.at(30), isAllDay: true)
        var declined = Fixture.event(start: Fixture.at(0.5), end: Fixture.at(30))
        declined.isDeclined = true
        let reminder = Fixture.reminder(due: Fixture.at(0.5))
        XCTAssertTrue(FullScreenAlerts.due(in: [allDay, declined, reminder], now: now,
                                           lead: lead, shown: []).isEmpty)
    }

    func testDueWindowStartsAtLeadAndEndsFiveMinutesAfterStart() {
        let tooEarly = Fixture.event(start: Fixture.at(2), end: Fixture.at(30))
        let inWindow = Fixture.event(start: Fixture.at(1), end: Fixture.at(30))
        let justStarted = Fixture.event(start: Fixture.at(-4), end: Fixture.at(30))
        let tooLate = Fixture.event(start: Fixture.at(-6), end: Fixture.at(30))

        let due = FullScreenAlerts.due(in: [tooEarly, inWindow, justStarted, tooLate],
                                       now: now, lead: lead, shown: [])
        XCTAssertEqual(Set(due.map(\.id)), [inWindow.id, justStarted.id])
    }

    func testAlreadyShownIsNotShownAgain() {
        let item = Fixture.event(start: Fixture.at(0.5), end: Fixture.at(30))
        XCTAssertTrue(FullScreenAlerts.due(in: [item], now: now, lead: lead,
                                           shown: [item.id]).isEmpty)
    }

    func testUpcomingOnlyWhenFireDateInFuture() {
        let later = Fixture.event(start: Fixture.at(10), end: Fixture.at(30))
        let inWindow = Fixture.event(start: Fixture.at(0.5), end: Fixture.at(30))
        XCTAssertEqual(FullScreenAlerts.upcoming(in: [later, inWindow], now: now, lead: lead)
                        .map(\.id), [later.id])
    }

    func testLeadZeroFiresAtStart() {
        let item = Fixture.event(start: Fixture.at(0), end: Fixture.at(30))
        XCTAssertEqual(FullScreenAlerts.due(in: [item], now: now, lead: 0, shown: []).count, 1)
    }

    // MARK: Link

    func testPrefersUrlFieldThenLocationThenNotes() {
        let field = URL(string: "https://zoom.us/j/1")!
        XCTAssertEqual(MeetingLink.find(url: field, location: "https://a.example",
                                        notes: nil), field)
        XCTAssertEqual(MeetingLink.find(url: nil, location: "Raum 3 https://meet.google.com/abc",
                                        notes: "https://b.example")?.host, "meet.google.com")
        XCTAssertEqual(MeetingLink.find(url: nil, location: "Raum 3",
                                        notes: "Beitreten: https://teams.microsoft.com/l/x")?.host,
                       "teams.microsoft.com")
    }

    /// Sicherheitsgrenze: Kalenderdaten aus fremden Einladungen dürfen weder Programme
    /// starten noch Laufwerke einbinden.
    func testRejectsNonWebSchemes() {
        for raw in ["file:///Applications/Calculator.app", "smb://host/share",
                    "x-apple.systempreferences:com.apple.Privacy", "javascript:alert(1)",
                    "ftp://host/file"] {
            XCTAssertFalse(MeetingLink.isOpenable(URL(string: raw)!), raw)
            XCTAssertNil(MeetingLink.find(url: URL(string: raw), location: raw, notes: raw), raw)
        }
    }

    func testFallsBackToWebLinkWhenUrlFieldIsNotWeb() {
        let result = MeetingLink.find(url: URL(string: "file:///etc/passwd"), location: nil,
                                      notes: "Link: https://zoom.us/j/9")
        XCTAssertEqual(result?.host, "zoom.us")
    }

    func testIgnoresLinkBeyondScanLimit() {
        let padding = String(repeating: "x", count: MeetingLink.maxScannedCharacters)
        XCTAssertNil(MeetingLink.find(url: nil, location: nil,
                                      notes: padding + " https://zoom.us/j/1"))
    }

    // MARK: Anzeige

    func testStatusText() {
        XCTAssertEqual(FullScreenAlertView.status(start: Fixture.at(3), now: now), "Beginnt in 3 Min.")
        XCTAssertEqual(FullScreenAlertView.status(start: Fixture.at(2.2), now: now), "Beginnt in 3 Min.")
        XCTAssertEqual(FullScreenAlertView.status(start: Fixture.at(0.5), now: now), "Beginnt gleich")
        XCTAssertEqual(FullScreenAlertView.status(start: Fixture.at(-2.5), now: now),
                       "Hat vor 2 Min. begonnen")
    }
}
