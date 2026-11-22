import XCTest

// SYNTHETISCH – erfundene Termine, keine echten Kalenderdaten.

/// 0.17.0 Nächster Termin an den Briefkasten fürs Schreibtischgerät: Nachricht, Adresse, Schlüssel.
@MainActor
final class KumikiTerminTests: XCTestCase {

    private func item(_ kind: AgendaItem.Kind = .event, title: String = "Zahnarzt", allDay: Bool = false,
                      start: Date? = Date(timeIntervalSince1970: 1_800_000_000)) -> AgendaItem {
        AgendaItem(id: "1", title: title, start: start, end: start?.addingTimeInterval(1800), isAllDay: allDay,
                   hasTime: true, kind: kind, sourceID: "k", color: RGBA(r: 1, g: 0.5, b: 0, a: 1), hasAlarms: false)
    }

    func testPayloadOnlyTitleAndStart() {
        let p = KumikiTermin.payload(item())
        XCTAssertEqual(p["v"] as? Int, 1)
        let t = p["termin"] as? [String: Any]
        XCTAssertEqual(t?["titel"] as? String, "Zahnarzt")
        XCTAssertEqual(t?["beginn"] as? Int, 1_800_000_000)
        XCTAssertEqual(Set(t?.keys.map { $0 } ?? []), ["titel", "beginn"], "keine weiteren Felder")
    }

    func testNoEventGivesNull() {
        XCTAssertTrue(KumikiTermin.payload(nil)["termin"] is NSNull)
        XCTAssertTrue(KumikiTermin.payload(item(allDay: true))["termin"] is NSNull)
        XCTAssertTrue(KumikiTermin.payload(item(.reminder(completed: false)))["termin"] is NSNull)
        XCTAssertTrue(KumikiTermin.payload(item(start: nil))["termin"] is NSNull)
    }

    func testTitleCleanedAndShortened() {
        XCTAssertEqual(KumikiTermin.cleanTitle("a\nb\tc"), "a b c")
        let long = String(repeating: "ä", count: 100)
        XCTAssertEqual(KumikiTermin.cleanTitle(long).count, KumikiTermin.maxTitle)
        XCTAssertEqual(KumikiTermin.cleanTitle("  Termin  "), "Termin")
    }

    func testURLAndKeyChecks() {
        XCTAssertNotNil(KumikiTermin.validURL("https://x.example/termin"))
        XCTAssertNil(KumikiTermin.validURL("http://x.example/termin"))
        XCTAssertNil(KumikiTermin.validURL("https://user:pw@x.example/termin"))
        XCTAssertNil(KumikiTermin.validURL("https://x.example/termin?k=1"))
        XCTAssertTrue(KumikiTermin.validKey(String(repeating: "a", count: 40)))
        XCTAssertFalse(KumikiTermin.validKey("kurz"))
        XCTAssertFalse(KumikiTermin.validKey(String(repeating: "a", count: 39) + " "))
    }
}
