import EventKit
import XCTest
@testable import Kalli

/// Deckt die Abbildung von EventKits Berechtigungsstatus auf Kallis
/// Anzeigezustand ab.
///
/// Anlass (2026-09-22): Kalli fragte die fehlende Berechtigung nicht mehr an und
/// zeigte den Zustand nirgends. Ursache war eine Bedingung, die auf einen
/// abgeleiteten Sammelzustand schaute (`access == .unknown`) statt auf die
/// Frage, die zählt — „steht eine der beiden auf `notDetermined`?". Diese Tests
/// halten die Abbildung fest, damit sie nicht wieder verrutscht.
final class PermissionTests: XCTestCase {

    func testMapsFullAccessToGranted() {
        XCTAssertEqual(CalendarStore.permission(.fullAccess), .granted)
    }

    func testMapsNotDeterminedToNotDetermined() {
        XCTAssertEqual(CalendarStore.permission(.notDetermined), .notDetermined)
    }

    func testMapsDeniedAndRestrictedSeparately() {
        XCTAssertEqual(CalendarStore.permission(.denied), .denied)
        XCTAssertEqual(CalendarStore.permission(.restricted), .restricted)
    }

    /// **Die inhaltliche Entscheidung dieses Typs:** `writeOnly` gilt es nur für
    /// Kalender und reicht Kalli nicht — die App liest ausschliesslich. Als
    /// „erteilt" anzuzeigen wäre eine Behauptung, während die Liste leer bleibt.
    func testWriteOnlyCountsAsDeniedBecauseKalliOnlyReads() {
        XCTAssertEqual(CalendarStore.permission(.writeOnly), .denied)
    }

    /// Sammelzustand für `refreshAccess()` (Audit-Fund K-C7): Wird der Zugriff
    /// später erteilt, muss aus `.denied` ein ladender Zustand werden.
    func testAccessFromIndividualPermissions() {
        XCTAssertEqual(CalendarStore.access(events: true, reminders: true), .granted)
        XCTAssertEqual(CalendarStore.access(events: false, reminders: false), .denied)
        XCTAssertEqual(CalendarStore.access(events: true, reminders: false),
                       .partial(events: true, reminders: false))
        XCTAssertEqual(CalendarStore.access(events: false, reminders: true),
                       .partial(events: false, reminders: true))
    }

    // MARK: - Ausgeblendete Quellen bei Teilzugriff (Review-Fund 2026-09-27)

    /// Der Fund: Erinnerungen entzogen, Kalender erlaubt. `found` enthält nur
    /// Kalender — die ausgeblendete Erinnerungsliste darf dabei NICHT still
    /// aus der Ausblend-Liste fallen. Sonst taucht sie bei erneuter Freigabe
    /// wieder auf, obwohl der Nutzer sie abgewählt hatte.
    func testPartialAccessKeepsHiddenIDsOfTheOtherKind() {
        let hidden: Set<String> = ["kalender-weg", "liste-versteckt"]
        let foundOnlyCalendars: Set<String> = ["kalender-sichtbar"]

        XCTAssertEqual(CalendarStore.hiddenAfterPrune(hidden, found: foundOnlyCalendars,
                                                      eventsReadable: true, remindersReadable: false),
                       hidden)
        XCTAssertEqual(CalendarStore.hiddenAfterPrune(hidden, found: ["liste-versteckt"],
                                                      eventsReadable: false, remindersReadable: true),
                       hidden)
    }

    func testNoAccessKeepsEverything() {
        let hidden: Set<String> = ["a", "b"]
        XCTAssertEqual(CalendarStore.hiddenAfterPrune(hidden, found: [],
                                                      eventsReadable: false, remindersReadable: false),
                       hidden)
    }

    /// Mit vollem Zugriff bleibt der Zweck erhalten: IDs gelöschter Kalender
    /// werden aufgeräumt.
    func testFullAccessPrunesVanishedSources() {
        let hidden: Set<String> = ["gibt-es-noch", "geloescht"]
        XCTAssertEqual(CalendarStore.hiddenAfterPrune(hidden, found: ["gibt-es-noch", "anderer"],
                                                      eventsReadable: true, remindersReadable: true),
                       ["gibt-es-noch"])
    }

    /// Jeder Zustand braucht eine Beschriftung — ein leeres Label in der
    /// Oberfläche wäre genau die Art stiller Lücke, die den Befund ausgelöst hat.
    func testEveryStateHasANonEmptyLabel() {
        for state: CalendarStore.Permission in [.notDetermined, .granted, .denied, .restricted] {
            XCTAssertFalse(state.label.isEmpty, "\(state) ohne Beschriftung")
        }
    }
}
