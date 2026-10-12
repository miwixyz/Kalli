import XCTest
@testable import Kalli

/// Wochentage hervorheben (Michael, 2026-10-12: „jeder Donnerstag soll die Farbe rot
/// haben"): ab Werk keiner, Wahl bleibt gespeichert, gilt für jede Woche.
@MainActor
final class WeekdayHighlightTests: XCTestCase {

    private var suite = ""
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        suite = "KalliTests.weekdayHighlight.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return cal
    }

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
    }

    func testNothingHighlightedByDefault() {
        let prefs = Preferences(defaults: defaults)
        XCTAssertTrue(prefs.weekdayHighlights.isEmpty)
        XCTAssertNil(prefs.highlight(for: day(2026, 10, 15), calendar: calendar))
    }

    func testEveryThursdayRedAndPersists() {
        Preferences(defaults: defaults).weekdayHighlights[5] = .red   // 5 = Donnerstag

        let prefs = Preferences(defaults: defaults)
        XCTAssertEqual(prefs.highlight(for: day(2026, 10, 15), calendar: calendar), .red)  // Do
        XCTAssertEqual(prefs.highlight(for: day(2026, 10, 22), calendar: calendar), .red)  // Do
        XCTAssertNil(prefs.highlight(for: day(2026, 10, 16), calendar: calendar))          // Fr
    }

    func testSettingNoneRemovesHighlight() {
        Preferences(defaults: defaults).weekdayHighlights[5] = .red
        Preferences(defaults: defaults).weekdayHighlights[5] = nil
        XCTAssertNil(Preferences(defaults: defaults).weekdayHighlights[5])
    }

    func testUnknownStoredValuesAreIgnored() {
        defaults.set(["5": "red", "6": "gelbgruen", "9": "blue", "x": "red"],
                     forKey: "weekdayHighlights")
        XCTAssertEqual(Preferences(defaults: defaults).weekdayHighlights, [5: .red])
    }
}
