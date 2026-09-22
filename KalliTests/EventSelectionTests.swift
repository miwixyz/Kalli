import XCTest
@testable import Kalli

/// Deckt die beiden Auswahlregeln der Menüleiste ab — **welcher** Termin dort
/// steht, wenn mehrere in Frage kommen.
///
/// Beide Regeln sind aus echten Fehlern entstanden, an zwei aufeinander
/// folgenden Tagen, und beide waren aus dem Code nicht als falsch erkennbar —
/// erst im Betrieb:
///
/// - **2026-09-21:** Ein Termin von *gestern* wurde als „läuft gerade"
///   angezeigt. `start <= now && end > now` ist formal richtig, trifft aber
///   auch mehrtägige Termine.
/// - **2026-09-22:** Bei „Praxis 08:00–16:00" stand acht Stunden lang die
///   Praxis in der Leiste, obwohl um 10:00 ein 30-Minuten-Termin darin lag.
///   `items.first` nahm den frühesten *Start*; gefragt ist das früheste *Ende*.
///
/// Die Tests hier sind der Grund, dass beides nicht zurückkommen kann.
final class EventSelectionTests: XCTestCase {

    private let cal = Fixture.calendar
    private let now = Fixture.now
    private let maxHours: Double = 12

    // MARK: - nextEvent

    func testNextEventPicksEarliestStart() {
        let later = Fixture.event(title: "später", start: Fixture.at(60), end: Fixture.at(90))
        let sooner = Fixture.event(title: "früher", start: Fixture.at(30), end: Fixture.at(45))

        let picked = CalendarStore.nextEvent(in: [later, sooner], now: now)

        XCTAssertEqual(picked?.title, "früher")
    }

    /// Der eigentliche Fund vom 2026-09-22: Zwei Termine um 10:00, die Leiste
    /// zeigte den, den EventKit zufällig zuerst lieferte.
    func testNextEventPrefersShorterOnEqualStart() {
        let long = Fixture.event(title: "Abfrage", start: Fixture.at(30), end: Fixture.at(150))
        let short = Fixture.event(title: "P&O", start: Fixture.at(30), end: Fixture.at(60))

        // Beide Reihenfolgen prüfen — sonst bestätigt der Test nur die
        // Eingabereihenfolge und nicht die Regel.
        XCTAssertEqual(CalendarStore.nextEvent(in: [long, short], now: now)?.title, "P&O")
        XCTAssertEqual(CalendarStore.nextEvent(in: [short, long], now: now)?.title, "P&O")
    }

    func testNextEventIgnoresAlreadyStarted() {
        let running = Fixture.event(title: "läuft", start: Fixture.at(-30), end: Fixture.at(30))

        XCTAssertNil(CalendarStore.nextEvent(in: [running], now: now))
    }

    func testNextEventIgnoresAllDayAndReminders() {
        let allDay = Fixture.event(title: "ganztägig", start: Fixture.at(60),
                                   end: Fixture.at(120), isAllDay: true)
        let task = Fixture.reminder(title: "Aufgabe", due: Fixture.at(60))

        XCTAssertNil(CalendarStore.nextEvent(in: [allDay, task], now: now))
    }

    func testNextEventNilOnEmptyList() {
        XCTAssertNil(CalendarStore.nextEvent(in: [], now: now))
    }

    // MARK: - runningEvent

    /// Die Regel, die den 22.09. ausgelöst hat: Praxis 08:00–16:00, darin ein
    /// kurzer Termin. Die Leiste muss den kurzen zeigen.
    func testRunningEventPrefersEarliestEnd() {
        let block = Fixture.event(title: "Praxis", start: Fixture.at(-240), end: Fixture.at(240))
        let inner = Fixture.event(title: "P&O", start: Fixture.at(-5), end: Fixture.at(25))
        let middle = Fixture.event(title: "Abfrage", start: Fixture.at(-5), end: Fixture.at(120))

        for order in [[block, inner, middle], [inner, middle, block], [middle, block, inner]] {
            XCTAssertEqual(
                CalendarStore.runningEvent(in: order, now: now, calendar: cal, maxHours: maxHours)?.title,
                "P&O",
                "Reihenfolge der Eingabe darf die Auswahl nicht bestimmen"
            )
        }
    }

    /// Nach dem Ende des kurzen Termins muss die Leiste zum nächstkürzeren
    /// wandern — von innen nach außen, nicht zurück auf den Tagesblock.
    func testRunningEventWandersOutwardWhenInnerEnds() {
        let block = Fixture.event(title: "Praxis", start: Fixture.at(-240), end: Fixture.at(240))
        let inner = Fixture.event(title: "P&O", start: Fixture.at(-60), end: Fixture.at(-30))
        let middle = Fixture.event(title: "Abfrage", start: Fixture.at(-60), end: Fixture.at(120))

        // `inner` ist um `now` bereits vorbei.
        XCTAssertEqual(
            CalendarStore.runningEvent(in: [block, inner, middle], now: now,
                                       calendar: cal, maxHours: maxHours)?.title,
            "Abfrage"
        )
    }

    /// Befund 2026-09-21: Ein mehrtägiger Termin, dessen Ende zufällig in der
    /// Zukunft liegt, galt als „läuft gerade".
    ///
    /// **Der Zeitpunkt ist hier tragend, nicht Beiwerk.** Die erste Fassung
    /// dieses Tests benutzte `now` = 12:00 und einen 21-Stunden-Termin — und
    /// bestand deshalb auch dann, wenn man die Tagesgrenzen-Prüfung aus dem
    /// Code entfernte: Die 12-Stunden-Regel schloss den Termin schon aus. Ein
    /// Test, der aus dem falschen Grund grün ist, ist schlimmer als keiner.
    /// Gefunden durch eine Mutationsprobe am 2026-09-22.
    ///
    /// Deshalb: `now` = 06:00 und ein Termin von 22:00 des Vortags bis 07:00 —
    /// neun Stunden, also innerhalb der Dauergrenze, laufend, und trotzdem an
    /// einem anderen Tag begonnen. Nur diese Kombination befragt die Regel.
    func testRunningEventIgnoresEventStartedOnAnotherDay() throws {
        let reference = Fixture.earlyMorning
        let overnight = Fixture.event(title: "gestern begonnen",
                                      start: Fixture.atEarly(-8 * 60),   // 22:00 Vortag
                                      end: Fixture.atEarly(60))          // 07:00 heute

        // Vorbedingungen des Tests selbst festschreiben: Er befragt die
        // Tagesgrenze nur, wenn der Termin an den anderen Regeln nicht schon
        // scheitert. Ohne diese drei Zusicherungen wäre nicht erkennbar, dass
        // er aus dem falschen Grund grün ist — genau das war er vorher.
        let start = try XCTUnwrap(overnight.start)
        let end = try XCTUnwrap(overnight.end)
        XCTAssertLessThanOrEqual(end.timeIntervalSince(start), maxHours * 3600,
                                 "sonst greift die Dauergrenze und die Tagesgrenze wird nie befragt")
        XCTAssertTrue(start <= reference && end > reference,
                      "der Termin muss um `now` tatsächlich laufen")
        XCTAssertFalse(cal.isDate(start, inSameDayAs: reference),
                       "der Termin muss an einem anderen Tag begonnen haben")

        XCTAssertNil(CalendarStore.runningEvent(in: [overnight], now: reference,
                                                calendar: cal, maxHours: maxHours))
    }

    /// Ein Zustand (Urlaub, Bereitschaft) ist kein Termin mit Fortschritt.
    func testRunningEventIgnoresOverlyLongEvents() {
        let standby = Fixture.event(title: "Bereitschaft",
                                    start: Fixture.at(-1),
                                    end: Fixture.at(13 * 60))

        XCTAssertNil(CalendarStore.runningEvent(in: [standby], now: now,
                                                calendar: cal, maxHours: maxHours))
    }

    /// Die Grenze selbst muss noch zählen, sonst verschiebt eine spätere
    /// Änderung sie unbemerkt.
    func testRunningEventAcceptsExactlyMaxHours() {
        let exact = Fixture.event(title: "genau 12 h",
                                  start: Fixture.at(-60),
                                  end: Fixture.at(11 * 60))

        XCTAssertEqual(
            CalendarStore.runningEvent(in: [exact], now: now, calendar: cal, maxHours: maxHours)?.title,
            "genau 12 h"
        )
    }

    func testRunningEventIgnoresAllDay() {
        let allDay = Fixture.event(title: "ganztägig", start: Fixture.at(-60),
                                   end: Fixture.at(60), isAllDay: true)

        XCTAssertNil(CalendarStore.runningEvent(in: [allDay], now: now,
                                                calendar: cal, maxHours: maxHours))
    }

    func testRunningEventNilWhenNothingRuns() {
        let future = Fixture.event(start: Fixture.at(30), end: Fixture.at(60))
        let past = Fixture.event(start: Fixture.at(-60), end: Fixture.at(-30))

        XCTAssertNil(CalendarStore.runningEvent(in: [future, past], now: now,
                                                calendar: cal, maxHours: maxHours))
    }

    /// Ein Termin, der genau jetzt endet, läuft nicht mehr.
    func testRunningEventExcludesEventEndingExactlyNow() {
        let ending = Fixture.event(start: Fixture.at(-30), end: now)

        XCTAssertNil(CalendarStore.runningEvent(in: [ending], now: now,
                                                calendar: cal, maxHours: maxHours))
    }
}
