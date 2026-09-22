import XCTest
@testable import Kalli

/// Deckt die Regel ab, **welcher** Termintext in der Menüleiste steht — und
/// wann **keiner**.
///
/// Anlass (Michael, 2026-09-22): „Wenn man *Nächsten Termin anzeigen* abwählt,
/// wird der aktuelle angezeigt. Es muss aber auswählbar sein, dass gar kein
/// Termin angezeigt wird."
///
/// Die Ursache war die eigene Änderung aus 0.1.1. Vorher hing der laufende
/// Termin allein an `showRunningProgress`, der nächste allein an
/// `showNextEventInMenuBar`; mit dem `??`-Rückfall von 0.1.1 überlebte der
/// laufende Termin das Abwählen des nächsten. Und `showRunningProgress`
/// abzuschalten war kein Ausweg — das nimmt auch den Fortschrittsbalken im
/// Popover weg.
///
/// Zwei Dinge, die diese Tests festschreiben: dass „aus" wirklich **nichts**
/// bedeutet, und dass der Popover-Fortschritt eine **andere** Frage ist als der
/// Leistentext.
final class MenuBarEventPartTests: XCTestCase {

    // MARK: - Der Fund

    /// Die Zeile, um die es ging: Schalter aus, Termin läuft → **nichts**.
    func testSwitchedOffShowsNothingEvenWhileAnEventIsRunning() {
        let part = MenuBarLabel.eventPart(showEvent: false, showProgress: true,
                                          next: nil, running: "Praxis noch 2:00 Std.")

        XCTAssertNil(part, "aus muss nichts heißen, auch wenn etwas läuft")
    }

    /// Und auch dann nichts, wenn beides vorläge.
    func testSwitchedOffShowsNothingEvenWithBothCandidates() {
        let part = MenuBarLabel.eventPart(showEvent: false, showProgress: true,
                                          next: "10:00 P&O in 8 Min.",
                                          running: "Praxis noch 2:00 Std.")

        XCTAssertNil(part)
    }

    // MARK: - Die Vorrang-Regel

    /// Was kommt, schlägt was läuft (Regel aus 0.1.1, hier festgeschrieben).
    func testNextEventWinsOverRunningEvent() {
        let part = MenuBarLabel.eventPart(showEvent: true, showProgress: true,
                                          next: "10:00 P&O in 8 Min.",
                                          running: "Praxis noch 2:00 Std.")

        XCTAssertEqual(part, "10:00 P&O in 8 Min.")
    }

    /// Steht nichts an, übernimmt der laufende Termin.
    func testRunningEventShownWhenNothingIsUpcoming() {
        let part = MenuBarLabel.eventPart(showEvent: true, showProgress: true,
                                          next: nil, running: "Praxis noch 2:00 Std.")

        XCTAssertEqual(part, "Praxis noch 2:00 Std.")
    }

    // MARK: - Der Fortschritt ist eine andere Frage

    /// Fortschritt aus → kein laufender Termin in der Leiste. Der nächste
    /// bleibt davon unberührt: Er ist kein Fortschritt.
    func testProgressOffHidesRunningButKeepsNext() {
        XCTAssertNil(MenuBarLabel.eventPart(showEvent: true, showProgress: false,
                                            next: nil, running: "Praxis noch 2:00 Std."))

        XCTAssertEqual(
            MenuBarLabel.eventPart(showEvent: true, showProgress: false,
                                   next: "10:00 P&O in 8 Min.", running: "Praxis noch 2:00 Std."),
            "10:00 P&O in 8 Min.",
            "der nächste Termin haengt nicht am Fortschritts-Schalter"
        )
    }

    // MARK: - Randfälle

    func testNothingAvailableShowsNothing() {
        XCTAssertNil(MenuBarLabel.eventPart(showEvent: true, showProgress: true,
                                            next: nil, running: nil))
    }

    /// Alle vier Schalterstellungen einmal durchgehen, damit keine Kombination
    /// unbeobachtet bleibt.
    func testAllSwitchCombinationsAreDefined() {
        let cases: [(Bool, Bool, String?)] = [
            (true,  true,  "naechster"),   // beides an  → nächster
            (true,  false, "naechster"),   // Fortschritt aus → nächster bleibt
            (false, true,  nil),           // Termin aus → nichts
            (false, false, nil),           // beides aus → nichts
        ]
        for (showEvent, showProgress, expected) in cases {
            let part = MenuBarLabel.eventPart(showEvent: showEvent, showProgress: showProgress,
                                              next: "naechster", running: "laufender")
            XCTAssertEqual(part, expected,
                           "showEvent=\(showEvent) showProgress=\(showProgress)")
        }
    }
}
