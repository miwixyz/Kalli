import XCTest
@testable import Kalli

/// Deckt die Nachprüfung nach dem Abhaken ab — insbesondere wiederkehrende
/// Erinnerungen (Audit-Fund K-C9, 2026-09-27).
///
/// **Nicht gemessen:** Laut Drittquellen bleibt beim Abhaken einer Serie
/// `isCompleted` am selben Objekt `false`, und die Fälligkeit rückt vor. Auf
/// Michaels Mac ist das nicht beobachtet. Die Regel akzeptiert deshalb beide
/// Varianten — diese Tests halten fest, dass sie es tut, nicht welche eintritt.
final class ReminderCompletionTests: XCTestCase {

    private let before = Fixture.now
    private let nextWeek = Fixture.at(7 * 24 * 60)

    func testPlainReminderConfirmedWhenFlagArrived() {
        XCTAssertTrue(CalendarStore.completionConfirmed(target: true, isCompleted: true, recurring: false,
                                                        dueBefore: before, dueAfter: before))
    }

    func testPlainReminderNotConfirmedWhenFlagMissing() {
        XCTAssertFalse(CalendarStore.completionConfirmed(target: true, isCompleted: false, recurring: false,
                                                         dueBefore: before, dueAfter: before))
    }

    /// Nicht-wiederkehrend: Eine verschobene Fälligkeit ist KEIN Beweis.
    func testPlainReminderMovedDueIsNotEnough() {
        XCTAssertFalse(CalendarStore.completionConfirmed(target: true, isCompleted: false, recurring: false,
                                                         dueBefore: before, dueAfter: nextWeek))
    }

    /// Der Fund: Serie abgehakt, Kennzeichen bleibt false, Fälligkeit rückt vor
    /// → Erfolg, keine Fehlermeldung.
    func testRecurringReminderConfirmedByAdvancedDueDate() {
        XCTAssertTrue(CalendarStore.completionConfirmed(target: true, isCompleted: false, recurring: true,
                                                        dueBefore: before, dueAfter: nextWeek))
    }

    /// Die andere mögliche Variante: Serie abgehakt, Kennzeichen steht.
    func testRecurringReminderConfirmedByFlag() {
        XCTAssertTrue(CalendarStore.completionConfirmed(target: true, isCompleted: true, recurring: true,
                                                        dueBefore: before, dueAfter: before))
    }

    /// Weder Kennzeichen noch Fälligkeit bewegt → wirklich nicht angekommen.
    func testRecurringReminderNotConfirmedWhenNothingChanged() {
        XCTAssertFalse(CalendarStore.completionConfirmed(target: true, isCompleted: false, recurring: true,
                                                         dueBefore: before, dueAfter: before))
        XCTAssertFalse(CalendarStore.completionConfirmed(target: true, isCompleted: false, recurring: true,
                                                         dueBefore: nil, dueAfter: nextWeek))
    }

    /// Zurücknehmen braucht das echte Kennzeichen — eine Datumsbewegung ist
    /// dafür kein Beleg.
    func testUncompleteNeedsTheFlag() {
        XCTAssertTrue(CalendarStore.completionConfirmed(target: false, isCompleted: false, recurring: true,
                                                        dueBefore: before, dueAfter: before))
        XCTAssertFalse(CalendarStore.completionConfirmed(target: false, isCompleted: true, recurring: true,
                                                         dueBefore: before, dueAfter: nextWeek))
    }
}
