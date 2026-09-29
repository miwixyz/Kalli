import XCTest
@testable import Kalli

/// Hell/Dunkel-Knopf (Michael, 2026-09-29): ab Werk System, Durchschalten
/// System → Hell → Dunkel → System, Wahl bleibt gespeichert.
final class AppearanceTests: XCTestCase {

    func testCyclesThroughAllModes() {
        XCTAssertEqual(AppearanceMode.system.next, .light)
        XCTAssertEqual(AppearanceMode.light.next, .dark)
        XCTAssertEqual(AppearanceMode.dark.next, .system)
    }

    @MainActor
    func testDefaultsToSystemAndPersists() throws {
        let suite = "KalliTests.appearance.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(Preferences(defaults: defaults).appearanceMode, .system)
        Preferences(defaults: defaults).appearanceMode = .dark
        XCTAssertEqual(Preferences(defaults: defaults).appearanceMode, .dark)
    }
}
