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
                CalendarStore.runningEvent(in: order, now: now, maxHours: maxHours)?.title,
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
                                       maxHours: maxHours)?.title,
            "Abfrage"
        )
    }

    /// **Regel geändert am 2026-09-27 (Audit-Fund K-C2).** Bis dahin prüfte
    /// dieser Test das Gegenteil: dass ein Termin von 22:00 bis 07:00 um 06:00
    /// *nicht* als laufend gilt („heute begonnen"). Genau das machte einen
    /// Nachtdienst unsichtbar. Die Tagesgrenze wirkte neben der Dauergrenze nur
    /// noch auf solche Termine — sie ist entfallen, die Dauergrenze bleibt.
    ///
    /// Die Vorbedingungen bleiben festgeschrieben: Der Test sagt nur etwas,
    /// wenn der Termin innerhalb der Dauergrenze liegt, gerade läuft und an
    /// einem anderen Tag begonnen hat.
    func testRunningEventIncludesOvernightShiftStillRunning() throws {
        var c = DateComponents()
        c.year = 2026; c.month = 9; c.day = 23; c.hour = 3
        let reference = try XCTUnwrap(cal.date(from: c))       // 03:00
        let shift = Fixture.event(title: "Nachtdienst",
                                  start: reference.addingTimeInterval(-5 * 3600),   // 22:00 Vortag
                                  end: reference.addingTimeInterval(3 * 3600))      // 06:00

        let start = try XCTUnwrap(shift.start)
        let end = try XCTUnwrap(shift.end)
        XCTAssertLessThanOrEqual(end.timeIntervalSince(start), maxHours * 3600)
        XCTAssertTrue(start <= reference && end > reference)
        XCTAssertFalse(cal.isDate(start, inSameDayAs: reference),
                       "der Termin muss an einem anderen Tag begonnen haben")

        XCTAssertEqual(CalendarStore.runningEvent(in: [shift], now: reference,
                                                  maxHours: maxHours)?.title,
                       "Nachtdienst")
    }

    /// Der ursprüngliche Befund vom 2026-09-21 — ein **mehrtägiger** Termin von
    /// gestern galt als „läuft gerade" — bleibt ausgeschlossen, jetzt über die
    /// Dauergrenze. Früher Morgen gewählt, damit der Termin wirklich gestern
    /// begann und jetzt läuft.
    func testRunningEventStillIgnoresMultiDayEventFromYesterday() {
        let multiDay = Fixture.event(title: "Messe",
                                     start: Fixture.atEarly(-20 * 60),   // gestern 10:00
                                     end: Fixture.atEarly(12 * 60))      // heute 18:00

        XCTAssertNil(CalendarStore.runningEvent(in: [multiDay], now: Fixture.earlyMorning,
                                                maxHours: maxHours))
    }

    // MARK: - Leisten-Fenster (K-C5)

    /// Die Leiste bekommt ein eigenes Zeitfenster um `now` — unabhängig vom
    /// Monat im Popover. Rückblick deckt jeden Termin, den `runningEvent`
    /// überhaupt zeigen darf (≤ 12 h), Vorausblick 24 h.
    func testBarWindowCoversRunningLimitAndNextDay() {
        let window = CalendarStore.barWindow(now: now)

        XCTAssertEqual(window.start, now.addingTimeInterval(-maxHours * 3600))
        XCTAssertEqual(window.end, now.addingTimeInterval(24 * 3600))
    }

    /// Der eigentliche Fund K-C5, am echten Objekt: Die Leiste rechnet aus
    /// `barItems`, **nie** aus `items` (dem Popover-Monat). Beide Listen
    /// tragen verschiedene Termine — steht der aus `items` in der Leiste, ist
    /// die Kopplung zurück.
    @MainActor
    func testMenuBarUsesBarItemsNotPopoverMonth() throws {
        let suite = "KalliTests.bar.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CalendarStore(prefs: Preferences(defaults: defaults))
        defer { store.stop() }

        let popoverMonth = Fixture.event(title: "aus dem Popover-Monat",
                                         start: Fixture.at(10), end: Fixture.at(20))
        let barNext = Fixture.event(title: "aus dem Leisten-Fenster",
                                    start: Fixture.at(30), end: Fixture.at(60))
        let barRunning = Fixture.event(title: "läuft", start: Fixture.at(-15), end: Fixture.at(15))

        store.setListsForTesting(items: [popoverMonth], barItems: [barNext, barRunning])
        store.refreshNextEvent(now: now)
        XCTAssertEqual(store.nextEvent?.title, "aus dem Leisten-Fenster",
                       "der frühere Termin aus `items` darf die Leiste nicht erreichen")
        XCTAssertEqual(store.runningEvent?.title, "läuft")

        // Popover zeigt einen anderen Monat, Leisten-Fenster leer → Leiste leer.
        store.setListsForTesting(items: [popoverMonth, barNext], barItems: [])
        store.refreshNextEvent(now: now)
        XCTAssertNil(store.nextEvent)
        XCTAssertNil(store.runningEvent)
    }

    /// Ein Zustand (Urlaub, Bereitschaft) ist kein Termin mit Fortschritt.
    func testRunningEventIgnoresOverlyLongEvents() {
        let standby = Fixture.event(title: "Bereitschaft",
                                    start: Fixture.at(-1),
                                    end: Fixture.at(13 * 60))

        XCTAssertNil(CalendarStore.runningEvent(in: [standby], now: now,
                                                maxHours: maxHours))
    }

    /// Die Grenze selbst muss noch zählen, sonst verschiebt eine spätere
    /// Änderung sie unbemerkt.
    func testRunningEventAcceptsExactlyMaxHours() {
        let exact = Fixture.event(title: "genau 12 h",
                                  start: Fixture.at(-60),
                                  end: Fixture.at(11 * 60))

        XCTAssertEqual(
            CalendarStore.runningEvent(in: [exact], now: now, maxHours: maxHours)?.title,
            "genau 12 h"
        )
    }

    func testRunningEventIgnoresAllDay() {
        let allDay = Fixture.event(title: "ganztägig", start: Fixture.at(-60),
                                   end: Fixture.at(60), isAllDay: true)

        XCTAssertNil(CalendarStore.runningEvent(in: [allDay], now: now,
                                                maxHours: maxHours))
    }

    func testRunningEventNilWhenNothingRuns() {
        let future = Fixture.event(start: Fixture.at(30), end: Fixture.at(60))
        let past = Fixture.event(start: Fixture.at(-60), end: Fixture.at(-30))

        XCTAssertNil(CalendarStore.runningEvent(in: [future, past], now: now,
                                                maxHours: maxHours))
    }

    /// Ein Termin, der genau jetzt endet, läuft nicht mehr.
    func testRunningEventExcludesEventEndingExactlyNow() {
        let ending = Fixture.event(start: Fixture.at(-30), end: now)

        XCTAssertNil(CalendarStore.runningEvent(in: [ending], now: now,
                                                maxHours: maxHours))
    }
}
