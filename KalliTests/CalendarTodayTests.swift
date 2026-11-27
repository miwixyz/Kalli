import XCTest

/// Widget-Klick (0.18.1): Kalli nimmt nur genau `kalli://kalender-heute` an (fremde Eingabe).
final class CalendarTodayTests: XCTestCase {
    func testWidgetLinkMatches() {
        XCTAssertTrue(CalendarToday.matches(CalendarToday.url))
        XCTAssertTrue(CalendarToday.matches(URL(string: "KALLI://Kalender-Heute")!))
        XCTAssertTrue(CalendarToday.matches(URL(string: "kalli://kalender-heute/")!))
    }

    func testOtherLinksAreIgnored() {
        let others = [
            "kalli://kalender-heute?datum=2020-01-01",
            "kalli://kalender-heute#x",
            "kalli://kalender-heute/irgendwas",
            "kalli://user@kalender-heute",
            "kalli://kalender-heute:80",
            "kalli://kalender",
            "kalli:",
            "https://kalender-heute",
            "ical://kalender-heute",
        ]
        for text in others {
            XCTAssertFalse(CalendarToday.matches(URL(string: text)!), text)
        }
    }

    func testScriptHasNoParametersAndFixedTarget() {
        let source = CalendarToday.source
        XCTAssertTrue(source.contains("tell application \"Calendar\""))
        XCTAssertFalse(source.contains("on run"))
        XCTAssertFalse(source.contains("do shell script"))
        XCTAssertEqual(source.components(separatedBy: "tell application").count, 2)
    }
}
