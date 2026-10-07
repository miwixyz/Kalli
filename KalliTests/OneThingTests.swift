import AppKit
import XCTest
@testable import Kalli

/// „Die eine Sache" (0.7.0): Bereinigung, Kürzung für die Leiste, Abgleich mit
/// Erinnerungen und Speicherung.
@MainActor
final class OneThingTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() {
        suite = "OneThingTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    private func make(_ lookup: @escaping @MainActor (String) -> OneThing.ReminderLookup = { _ in .unknown }) -> OneThing {
        OneThing(defaults: defaults, lookup: lookup)
    }

    // MARK: Reine Logik

    func testCleanMakesOneLineAndCaps() {
        XCTAssertEqual(OneThing.clean("  Angebot\n\tKino X   fertig \n"), "Angebot Kino X fertig")
        XCTAssertEqual(OneThing.clean(String(repeating: "a", count: 500)).count, OneThing.maxChars)
        XCTAssertEqual(OneThing.clean(" \n\t "), "")
    }

    func testBarTextShortensLongTextWithEllipsis() {
        XCTAssertEqual(OneThing.barText("Kurz"), "Kurz")
        let long = OneThing.barText(String(repeating: "x", count: 80))
        XCTAssertEqual(long.count, OneThing.barMaxChars)
        XCTAssertTrue(long.hasSuffix("…"))
        XCTAssertEqual(OneThing.barText(String(repeating: "y", count: OneThing.barMaxChars)).count, OneThing.barMaxChars)
    }

    func testOutcomeKeepsWhenUncheckableClearsWhenGoneOrDone() {
        XCTAssertEqual(OneThing.outcome(of: .unknown, currentText: "A"), .keep)
        XCTAssertEqual(OneThing.outcome(of: .gone, currentText: "A"), .clear)
        XCTAssertEqual(OneThing.outcome(of: .found(.init(title: "A", isCompleted: true)), currentText: "A"), .clear)
        XCTAssertEqual(OneThing.outcome(of: .found(.init(title: "A", isCompleted: false)), currentText: "A"), .keep)
        XCTAssertEqual(OneThing.outcome(of: .found(.init(title: "B neu", isCompleted: false)), currentText: "A"), .rename("B neu"))
        XCTAssertEqual(OneThing.outcome(of: .found(.init(title: "  ", isCompleted: false)), currentText: "A"), .clear)
    }

    // MARK: Modell

    func testFreeTextIsStoredAndRestored() {
        make().set(text: "Steuer\nabgeben")
        let again = make()
        XCTAssertEqual(again.text, "Steuer abgeben")
        XCTAssertNil(again.reminderID)
        XCTAssertTrue(again.isSet)
    }

    func testCompletedReminderDisappearsOnReconcile() {
        var state = OneThing.ReminderLookup.found(.init(title: "Zahnarzt anrufen", isCompleted: false))
        let thing = make { _ in state }
        thing.set(reminderID: "R1", title: "Zahnarzt anrufen")
        thing.reconcile()
        XCTAssertEqual(thing.text, "Zahnarzt anrufen")
        state = .found(.init(title: "Zahnarzt anrufen", isCompleted: true))
        thing.reconcile()
        XCTAssertFalse(thing.isSet)
        XCTAssertNil(defaults.string(forKey: "oneThingReminderID"))
        XCTAssertEqual(defaults.string(forKey: "oneThingText"), "")
    }

    func testReminderSurvivesWhenItCannotBeChecked() {
        let thing = make { _ in .unknown }
        thing.set(reminderID: "R1", title: "Zahnarzt anrufen")
        // Neustart ohne Erinnerungs-Berechtigung: nichts löschen.
        let restarted = make { _ in .unknown }
        XCTAssertEqual(restarted.text, "Zahnarzt anrufen")
        XCTAssertEqual(restarted.reminderID, "R1")
        _ = thing
    }

    func testRenamedReminderUpdatesText() {
        let thing = make { _ in .found(.init(title: "Zahnarzt Dr. Lang anrufen", isCompleted: false)) }
        thing.set(reminderID: "R1", title: "Zahnarzt anrufen")
        thing.reconcile()
        XCTAssertEqual(thing.text, "Zahnarzt Dr. Lang anrufen")
        XCTAssertEqual(thing.reminderID, "R1")
    }

    func testFreeTextReplacesReminderAndClearRemovesAll() {
        let thing = make { _ in .gone }
        thing.set(reminderID: "R1", title: "Zahnarzt anrufen")
        thing.set(text: "Präsentation fertig")
        XCTAssertNil(thing.reminderID)
        thing.reconcile()   // .gone darf freien Text nicht löschen
        XCTAssertEqual(thing.text, "Präsentation fertig")
        thing.clear()
        XCTAssertFalse(thing.isSet)
    }

    func testServiceSetsSelectedText() {
        let thing = make()
        let service = OneThingService(oneThing: thing)
        let board = NSPasteboard(name: NSPasteboard.Name("OneThingTests-\(UUID().uuidString)"))
        board.clearContents()
        board.setString("Rechnung\nCineSocial schreiben", forType: .string)
        var error: NSString?
        service.setOneThing(board, userData: nil, error: &error)
        XCTAssertNil(error)
        XCTAssertEqual(thing.text, "Rechnung CineSocial schreiben")

        board.clearContents()
        board.setString("   ", forType: .string)
        service.setOneThing(board, userData: nil, error: &error)
        XCTAssertNotNil(error)
        XCTAssertEqual(thing.text, "Rechnung CineSocial schreiben")
    }
}
