import Foundation
import Observation
import OSLog
import Sparkle
import UserNotifications

/// Automatische Updates über Sparkle.
///
/// **Das ist der einzige Netzwerkzugriff der App.** Bis Version 0.3.1 sendete
/// Kalli nichts; mit dem Updater kontaktiert es
/// `raw.githubusercontent.com` und später `github.com`, und übermittelt dabei —
/// wie jeder HTTP-Aufruf — IP-Adresse und implizit die installierte Version.
/// Kein Tracking, keine Kennung, aber Verkehr, wo vorher keiner war. Deshalb
/// steht es in `RECHTLICHES.md` und in der Hilfe, nicht nur hier.
///
/// **Zwei Vertrauensanker, beide von Sparkle geprüft**, bevor irgendetwas
/// ersetzt wird:
///   1. **EdDSA-Signatur** des Archivs gegen `SUPublicEDKey` aus der
///      `Info.plist`. Der private Teil liegt ausschließlich im Login-
///      Schlüsselbund des Entwickler-Macs, nie im Repo.
///   2. **Developer-ID-Signatur** des entpackten Bundles.
/// Ein Angreifer bräuchte beide Schlüssel. Ein manipulierter Appcast allein
/// liefert nichts aus.
///
/// **`SUEnableAutomaticChecks` ist bewusst NICHT gesetzt.** Sparkle fragt
/// dadurch beim ersten Mal, ob automatisch gesucht werden darf. Gleiche Haltung
/// wie bei Kalender-Berechtigung und Systemmitteilungen: Was von sich aus das
/// Netz benutzt, wird erteilt, nicht geerbt.
///
/// Vollständiger Entwurf samt STRIDE-Durchgang und getragenen Restrisiken:
/// `docs/AUTO-UPDATE-DESIGN.md`.
@MainActor
@Observable
final class Updater {

    /// Version eines Updates, das eine **automatische** Prüfung gefunden hat
    /// und das noch niemand angesehen hat. Das Popover zeigt es am Update-Knopf.
    private(set) var bereitesUpdate: String?

    /// Kennung der Update-Mitteilung — `EventAlerts` erkennt daran den Klick.
    nonisolated static let erinnerungsID = "kalli.update"

    /// `startingUpdater: true` startet die Hintergrundprüfung — die aber nur
    /// läuft, wenn der Nutzer sie erlaubt hat (siehe oben).
    private let controller: SPUStandardUpdaterController

    /// Sparkle hält den Delegate nur schwach — ohne diese Referenz wäre er
    /// sofort weg und die Erinnerung stumm.
    private let erinnerung: SanfteErinnerung

    init() {
        let e = SanfteErinnerung()
        erinnerung = e
        // Der Delegate prüft nichts und lockert nichts — er entscheidet nur,
        // WIE ein gefundenes Update gezeigt wird. Signaturprüfung, Appcast und
        // Installation bleiben Sparkles Standardweg.
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: e
        )
        e.onChange = { [weak self] version in self?.bereitesUpdate = version }
        // Klick auf die Mitteilung -> Update-Fenster. Weil es jetzt eine
        // Nutzeraktion ist, darf es nach vorn (gemessen 2026-09-24: Platz 1).
        NotificationCenter.default.addObserver(
            forName: .kalliUpdateErinnerungGeklickt, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkForUpdates() }
        }
        // Prüfhaken: löst eine Hintergrundprüfung aus wie der Zeitplan — erst
        // nach 2 Minuten, denn direkt nach dem Start zeigt Sparkle das Fenster
        // absichtlich selbst im Vordergrund („launched recently", gemessen
        // 2026-09-24). Der Erinnerungsweg ist nur später erreichbar.
        if ProcessInfo.processInfo.arguments.contains("-KalliHintergrundpruefung") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 120) { [controller] in
                controller.updater.checkForUpdatesInBackground()
            }
        }
    }

    /// Prüft auf Anforderung — der Weg, den der Menüeintrag nimmt.
    ///
    /// Sparkle zeigt danach selbst an, was es gefunden hat, **einschließlich
    /// „kein Update vorhanden"**. Genau deshalb wird hier nichts verschluckt:
    /// Ein Knopf, der nichts sichtbar tut, sieht wie ein kaputter Knopf aus.
    func checkForUpdates() {
        controller.updater.checkForUpdates()
    }

    /// Ob gerade geprüft werden kann. Während einer laufenden Prüfung `false`;
    /// der Knopf wird dann ausgegraut statt doppelt auslösbar zu sein.
    var canCheck: Bool {
        controller.updater.canCheckForUpdates
    }

    /// Ob der Nutzer die automatische Suche erlaubt hat. Nur zur Anzeige —
    /// gesetzt wird sie von Sparkles eigenem Dialog, nicht von uns. Ein
    /// gespiegelter Schalter würde beim ersten Eingriff von außen falsch, wie
    /// beim Autostart (`LoginItem`).
    var automaticallyChecks: Bool {
        controller.updater.automaticallyChecksForUpdates
    }
}

extension Notification.Name {
    static let kalliUpdateErinnerungGeklickt = Notification.Name("kalli.update.geklickt")
}

/// Sanfte Update-Erinnerung statt eines Fensters hinter anderen Apps.
///
/// Sparkle sagt selbst, was bei Apps ohne Dock-Symbol passiert: Findet eine
/// **automatische** Prüfung ein Update, zeigt es das Fenster „immediately, but
/// behind other running applications" (`SPUStandardUserDriverDelegate.h`).
/// macOS lässt eine App ohne vorherige Nutzeraktion nicht nach vorn — das
/// Fenster lag also unsichtbar hinten (Michael, 2026-09-24: „das irritiert").
///
/// Stattdessen: Mitteilung + Hinweis am Update-Knopf. Erst ein Klick öffnet
/// das Fenster, und dann steht es vorn. Prüfungen per Knopf laufen unverändert
/// über Sparkle — die ruft diese Methoden gar nicht erst auf.
@MainActor
private final class SanfteErinnerung: NSObject, @preconcurrency SPUStandardUserDriverDelegate {
    var onChange: ((String?) -> Void)?

    /// Einmal pro gefundenem Update — damit „kam ein Fenster, und wenn ja,
    /// warum" nachträglich beantwortbar ist. Am 2026-09-24 war es das nicht.
    private static let log = Logger(subsystem: "com.kalli.app", category: "update")

    var supportsGentleScheduledUpdateReminders: Bool { true }

    /// Nie Sparkle selbst ein Fenster für eine AUTOMATISCHE Prüfung zeigen
    /// lassen — auch nicht bei „immediate focus" (App gerade gestartet).
    /// Gemessen 2026-09-24 unter macOS 27 an Tippi: Sparkle meldete „Fenster
    /// vorn", tatsächlich lag es auf Platz 3 hinter zwei anderen. Nur eine
    /// Nutzeraktion bringt ein Fenster nach vorn — also immer die Erinnerung.
    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        false
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        guard !handleShowingUpdate else {
            Self.log.notice("Update \(update.displayVersionString, privacy: .public): Sparkle zeigt das Fenster selbst (Vordergrund)")
            return
        }
        onChange?(update.displayVersionString)
        guard !state.userInitiated else { return }
        Self.log.notice("Update \(update.displayVersionString, privacy: .public): sanfte Erinnerung statt Fenster (Mitteilung + Knopf)")
        let inhalt = UNMutableNotificationContent()
        inhalt.title = "Kalli \(update.displayVersionString) ist da"
        inhalt.body = "Klicken, um das Update anzusehen."
        // Nicht still: Ohne Mitteilungs-Erlaubnis bleibt nur der Hinweis am
        // Update-Knopf — das Protokoll muss es sagen.
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: Updater.erinnerungsID, content: inhalt, trigger: nil)
        ) { fehler in
            if let fehler {
                Self.log.notice("Update-Mitteilung nicht zugestellt (\(fehler.localizedDescription, privacy: .public)) — nur Hinweis am Knopf")
            }
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        aufraeumen()
    }

    func standardUserDriverWillFinishUpdateSession() {
        aufraeumen()
    }

    private func aufraeumen() {
        onChange?(nil)
        let c = UNUserNotificationCenter.current()
        c.removeDeliveredNotifications(withIdentifiers: [Updater.erinnerungsID])
        c.removePendingNotificationRequests(withIdentifiers: [Updater.erinnerungsID])
    }
}
