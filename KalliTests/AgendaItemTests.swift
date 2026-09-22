import XCTest
@testable import Kalli

/// Deckt die Beschriftungen und Zustandsfragen eines Eintrags ab.
///
/// Zwei davon stammen aus echten Fehlern:
/// - **„00:00" bei Erinnerungen** (2026-09-21): Ein Fälligkeitsdatum ohne
///   Zeitanteil ist Mitternacht. Ungeprüft stand überall „00:00" statt nichts.
/// - **Eine überfällige Aufgabe ist nicht erledigt, sondern das Gegenteil
///   davon.** Sie als „vorbei" auszublenden würde genau das Wichtigste
///   verstecken.
final class AgendaItemTests: XCTestCase {

    private let now = Fixture.now

    private var timeFormatter: DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.timeZone = TimeZone(identifier: "Europe/Berlin")
        f.dateFormat = "HH:mm"
        return f
    }

    // MARK: - remainingLabel

    func testRemainingLabelUsesMinutesUnderOneHour() {
        let item = Fixture.event(start: Fixture.at(-10), end: Fixture.at(25))

        XCTAssertEqual(item.remainingLabel(at: now), "noch 25 Min.")
    }

    func testRemainingLabelUsesHoursAndPadsMinutes() {
        let item = Fixture.event(start: Fixture.at(-10), end: Fixture.at(125))

        // 2:05, nicht 2:5 — ohne Auffüllen liest sich das wie 2:50.
        XCTAssertEqual(item.remainingLabel(at: now), "noch 2:05 Std.")
    }

    func testRemainingLabelNilWhenNotRunning() {
        let future = Fixture.event(start: Fixture.at(30), end: Fixture.at(60))
        let past = Fixture.event(start: Fixture.at(-60), end: Fixture.at(-30))

        XCTAssertNil(future.remainingLabel(at: now))
        XCTAssertNil(past.remainingLabel(at: now))
    }

    func testRemainingLabelNilForAllDay() {
        let allDay = Fixture.event(start: Fixture.at(-60), end: Fixture.at(60), isAllDay: true)

        XCTAssertNil(allDay.remainingLabel(at: now))
    }

    // MARK: - startsInLabel

    func testStartsInLabelSaysGleichUnderOneMinute() {
        let item = Fixture.event(start: now.addingTimeInterval(30), end: Fixture.at(30))

        XCTAssertEqual(item.startsInLabel(at: now), "gleich")
    }

    func testStartsInLabelMinutesAndHours() {
        XCTAssertEqual(
            Fixture.event(start: Fixture.at(13), end: Fixture.at(43)).startsInLabel(at: now),
            "in 13 Min."
        )
        XCTAssertEqual(
            Fixture.event(start: Fixture.at(150), end: Fixture.at(180)).startsInLabel(at: now),
            "in 2:30 Std."
        )
    }

    func testStartsInLabelNilForStartedEvent() {
        let started = Fixture.event(start: Fixture.at(-1), end: Fixture.at(30))

        XCTAssertNil(started.startsInLabel(at: now))
    }

    // MARK: - progress

    func testProgressIsHalfwayAtMidpoint() {
        let item = Fixture.event(start: Fixture.at(-30), end: Fixture.at(30))

        XCTAssertEqual(try XCTUnwrap(item.progress(at: now)), 0.5, accuracy: 0.0001)
    }

    func testProgressNilOutsideRunAndForAllDay() {
        XCTAssertNil(Fixture.event(start: Fixture.at(30), end: Fixture.at(60)).progress(at: now))
        XCTAssertNil(Fixture.event(start: Fixture.at(-60), end: Fixture.at(-30)).progress(at: now))
        XCTAssertNil(Fixture.event(start: Fixture.at(-30), end: Fixture.at(30),
                                   isAllDay: true).progress(at: now))
    }

    /// Ein Termin ohne Dauer hat keinen Fortschritt — sonst Division durch Null.
    func testProgressNilWhenStartEqualsEnd() {
        let instant = Fixture.event(start: now, end: now)

        XCTAssertNil(instant.progress(at: now))
    }

    // MARK: - isOver

    func testIsOverForFinishedTimedEvent() {
        XCTAssertTrue(Fixture.event(start: Fixture.at(-60), end: Fixture.at(-30)).isOver(at: now))
        XCTAssertFalse(Fixture.event(start: Fixture.at(-30), end: Fixture.at(30)).isOver(at: now))
    }

    /// Ganztägige betreffen den ganzen Tag, auch abends noch.
    func testAllDayIsNeverOver() {
        let allDay = Fixture.event(start: Fixture.at(-600), end: Fixture.at(-60), isAllDay: true)

        XCTAssertFalse(allDay.isOver(at: now))
    }

    /// Die wichtigste Zeile dieser Datei: Eine überfällige Aufgabe darf der
    /// Vergangenheitsfilter nicht verstecken.
    func testOverdueReminderIsNeverOver() {
        let overdue = Fixture.reminder(due: Fixture.at(-600))

        XCTAssertFalse(overdue.isOver(at: now))
    }

    // MARK: - timeLabel

    func testTimeLabelForAllDay() {
        let allDay = Fixture.event(start: now, end: Fixture.at(600), isAllDay: true)

        XCTAssertEqual(allDay.timeLabel(using: timeFormatter), "ganztägig")
    }

    func testTimeLabelShowsRangeForTimedEvent() {
        let item = Fixture.event(start: Fixture.at(-120), end: Fixture.at(-60))

        XCTAssertEqual(item.timeLabel(using: timeFormatter), "10:00–11:00")
    }

    func testTimeLabelShowsSingleTimeForReminder() {
        let task = Fixture.reminder(due: Fixture.at(-120))

        XCTAssertEqual(task.timeLabel(using: timeFormatter), "10:00")
    }

    /// Der „00:00"-Fehler vom 2026-09-21: Eine Erinnerung nur mit Tag, ohne
    /// Uhrzeit, darf keine Zeit anzeigen.
    func testTimeLabelEmptyForReminderWithoutClockTime() {
        let dayOnly = Fixture.reminder(due: Fixture.at(-720), hasTime: false)

        XCTAssertEqual(dayOnly.timeLabel(using: timeFormatter), "")
    }

    // MARK: - Kennung

    func testEventIDDiffersPerOccurrence() {
        let a = CalendarStore.eventID(base: "SERIE", start: Fixture.at(0))
        let b = CalendarStore.eventID(base: "SERIE", start: Fixture.at(240))

        XCTAssertNotEqual(a, b, "zwei Vorkommen derselben Serie brauchen eigene Kennungen")
    }

    func testEventIDIsStableForSameOccurrence() {
        let a = CalendarStore.eventID(base: "SERIE", start: Fixture.at(0))
        let b = CalendarStore.eventID(base: "SERIE", start: Fixture.at(0))

        XCTAssertEqual(a, b, "sonst wäre nach jedem Neuladen eine neue Mitteilung fällig")
    }

    func testEventIDFallsBackWithoutStart() {
        XCTAssertEqual(CalendarStore.eventID(base: "SERIE", start: nil), "SERIE")
    }

    /// Ohne Termin-ID muss trotzdem eine brauchbare, eindeutige Kennung
    /// herauskommen — sonst kollabieren alle solchen Einträge in `ForEach`
    /// auf eine Zeile.
    func testEventIDWithoutBaseIsNonEmptyAndUnique() {
        let a = CalendarStore.eventID(base: nil, start: Fixture.at(0))
        let b = CalendarStore.eventID(base: nil, start: Fixture.at(0))

        XCTAssertFalse(a.isEmpty)
        XCTAssertNotEqual(a, b)
    }
}
