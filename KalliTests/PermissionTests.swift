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

    /// Jeder Zustand braucht eine Beschriftung — ein leeres Label in der
    /// Oberfläche wäre genau die Art stiller Lücke, die den Befund ausgelöst hat.
    func testEveryStateHasANonEmptyLabel() {
        for state: CalendarStore.Permission in [.notDetermined, .granted, .denied, .restricted] {
            XCTAssertFalse(state.label.isEmpty, "\(state) ohne Beschriftung")
        }
    }
}
