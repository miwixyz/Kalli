import XCTest
@testable import Kalli

/// Deckt ab, **an welchen Tagen** ein Eintrag steht und **welche Tage** geladen
/// werden.
///
/// Zwei Audit-Funde vom 2026-09-27:
///
/// - **K-C2:** Getimte Termine standen nur an ihrem Starttag. Ein Nachtdienst
///   22–06 fehlte am Folgetag in Raster und Tagesliste.
/// - **K-C1:** Geladen wurde „Monat ±7 Tage", das Raster zeigt 42 Tage ab
///   Wochenbeginn. Im September 2026 fehlten 08.–11.10., im Februar 2027
///   08.–14.03.
final class DayOverlapTests: XCTestCase {

    private let cal = Fixture.calendar

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = h; c.minute = min
        return cal.date(from: c)!
    }

    // MARK: - Überlappung (K-C2)

    func testOvernightEventAppearsOnBothDays() {
        let shift = Fixture.event(title: "Nachtdienst",
                                  start: date(2026, 9, 22, 22), end: date(2026, 9, 23, 6))

        XCTAssertTrue(CalendarStore.occurs(shift, on: date(2026, 9, 22), calendar: cal))
        XCTAssertTrue(CalendarStore.occurs(shift, on: date(2026, 9, 23), calendar: cal),
                      "der Folgetag muss den Nachtdienst zeigen — das war der Fund")
        XCTAssertFalse(CalendarStore.occurs(shift, on: date(2026, 9, 24), calendar: cal))
        XCTAssertFalse(CalendarStore.occurs(shift, on: date(2026, 9, 21), calendar: cal))
    }

    /// Endet ein Termin exakt um Mitternacht, gehört er nicht zum Folgetag —
    /// sonst stünde jeder Abendtermin bis 24:00 auch morgen früh in der Liste.
    func testEventEndingExactlyAtMidnightDoesNotSpillOver() {
        let evening = Fixture.event(title: "Abend",
                                    start: date(2026, 9, 22, 20), end: date(2026, 9, 23, 0))

        XCTAssertTrue(CalendarStore.occurs(evening, on: date(2026, 9, 22), calendar: cal))
        XCTAssertFalse(CalendarStore.occurs(evening, on: date(2026, 9, 23), calendar: cal))
    }

    /// Termine ohne Dauer (end == start) bleiben an ihrem Tag — auch um 00:00.
    func testZeroDurationEventStaysOnItsDay() {
        let atMidnight = Fixture.event(start: date(2026, 9, 23, 0), end: date(2026, 9, 23, 0))
        let lateEvening = Fixture.event(start: date(2026, 9, 22, 23), end: date(2026, 9, 22, 23))

        XCTAssertTrue(CalendarStore.occurs(atMidnight, on: date(2026, 9, 23), calendar: cal))
        XCTAssertFalse(CalendarStore.occurs(atMidnight, on: date(2026, 9, 22), calendar: cal))
        XCTAssertTrue(CalendarStore.occurs(lateEvening, on: date(2026, 9, 22), calendar: cal))
        XCTAssertFalse(CalendarStore.occurs(lateEvening, on: date(2026, 9, 23), calendar: cal))
    }

    /// Erinnerungen haben kein Ende — sie gehören an den Fälligkeitstag, auch
    /// ohne Uhrzeit (Mitternacht).
    func testRemindersStayOnDueDay() {
        let noTime = Fixture.reminder(due: date(2026, 9, 23), hasTime: false)
        let timed = Fixture.reminder(due: date(2026, 9, 23, 18))

        XCTAssertTrue(CalendarStore.occurs(noTime, on: date(2026, 9, 23), calendar: cal))
        XCTAssertFalse(CalendarStore.occurs(noTime, on: date(2026, 9, 22), calendar: cal))
        XCTAssertTrue(CalendarStore.occurs(timed, on: date(2026, 9, 23), calendar: cal))
        XCTAssertFalse(CalendarStore.occurs(timed, on: date(2026, 9, 24), calendar: cal))
    }

    /// Sommerzeit-Ende 25.10.2026 (03:00 → 02:00, der Tag hat 25 Stunden).
    /// Tagesgrenzen kommen aus `startOfDay`/`date(byAdding: .day)`, nicht aus
    /// 24 × 3600 — sonst verrutschte der Folgetag um eine Stunde.
    func testOvernightShiftAcrossDaylightSavingEnd() throws {
        let shift = Fixture.event(title: "Nachtdienst",
                                  start: date(2026, 10, 24, 22), end: date(2026, 10, 25, 6))
        let start = try XCTUnwrap(shift.start)
        let end = try XCTUnwrap(shift.end)
        XCTAssertEqual(end.timeIntervalSince(start), 9 * 3600,
                       "Vorbedingung: die Nacht ist durch die Zeitumstellung 9 statt 8 Stunden lang")

        XCTAssertTrue(CalendarStore.occurs(shift, on: date(2026, 10, 24), calendar: cal))
        XCTAssertTrue(CalendarStore.occurs(shift, on: date(2026, 10, 25), calendar: cal))
        XCTAssertFalse(CalendarStore.occurs(shift, on: date(2026, 10, 26), calendar: cal))

        // Am 25-Stunden-Tag: 23:30–00:30 gehört an beide Tage, 22:00–00:00 nur an den 25.
        let late = Fixture.event(start: date(2026, 10, 25, 23, 30), end: date(2026, 10, 26, 0, 30))
        let untilMidnight = Fixture.event(start: date(2026, 10, 25, 22), end: date(2026, 10, 26, 0))
        XCTAssertTrue(CalendarStore.occurs(late, on: date(2026, 10, 25), calendar: cal))
        XCTAssertTrue(CalendarStore.occurs(late, on: date(2026, 10, 26), calendar: cal))
        XCTAssertTrue(CalendarStore.occurs(untilMidnight, on: date(2026, 10, 25), calendar: cal))
        XCTAssertFalse(CalendarStore.occurs(untilMidnight, on: date(2026, 10, 26), calendar: cal))
    }

    func testOrdinaryDayEventUnchanged() {
        let meeting = Fixture.event(start: date(2026, 9, 22, 10), end: date(2026, 9, 22, 11))

        XCTAssertTrue(CalendarStore.occurs(meeting, on: date(2026, 9, 22, 15), calendar: cal))
        XCTAssertFalse(CalendarStore.occurs(meeting, on: date(2026, 9, 23), calendar: cal))
    }

    // MARK: - Ladebereich = Raster (K-C1)

    private var mondayFirst: Calendar {
        var c = cal
        c.firstWeekday = 2
        return c
    }

    /// September 2026 beginnt an einem Dienstag: Raster Mo 31.08. bis So 11.10.
    /// Der alte Ladebereich endete am 08.10. — vier sichtbare Tage ohne Daten.
    func testLoadRangeMatchesRasterSeptember2026() throws {
        let range = try XCTUnwrap(MonthRaster.interval(for: date(2026, 9, 15), calendar: mondayFirst))

        XCTAssertEqual(range.start, date(2026, 8, 31))
        XCTAssertEqual(range.end, date(2026, 10, 12), "letzter Rastertag So 11.10., exklusives Ende")
        XCTAssertTrue(range.contains(date(2026, 10, 11, 12)),
                      "der 11.10. steht im Raster und muss geladen sein — das war der Fund")
    }

    /// Februar 2027 beginnt an einem Montag: Raster 01.02. bis So 14.03.
    /// Der alte Ladebereich endete am 08.03. — eine ganze sichtbare Woche leer.
    func testLoadRangeMatchesRasterFebruary2027() throws {
        let range = try XCTUnwrap(MonthRaster.interval(for: date(2027, 2, 10), calendar: mondayFirst))

        XCTAssertEqual(range.start, date(2027, 2, 1))
        XCTAssertEqual(range.end, date(2027, 3, 15))
        XCTAssertTrue(range.contains(date(2027, 3, 14, 12)))
    }

    /// Jeder Tag, den das Raster zeigt, liegt im Ladebereich — und es sind 42.
    /// Mit Sommerzeitwechsel (März 2026) als Rand.
    func testEveryRasterDayIsInsideLoadRange() throws {
        for month in [date(2026, 9, 1), date(2027, 2, 1), date(2026, 3, 1), date(2026, 10, 31)] {
            let days = MonthRaster.days(for: month, calendar: mondayFirst)
            let range = try XCTUnwrap(MonthRaster.interval(for: month, calendar: mondayFirst))

            XCTAssertEqual(days.count, MonthRaster.dayCount)
            for day in days {
                XCTAssertTrue(range.contains(day), "\(day) fehlt im Ladebereich")
            }
            let lastDay = try XCTUnwrap(days.last)
            XCTAssertEqual(range.end, cal.date(byAdding: .day, value: 1, to: lastDay))
        }
    }
}
