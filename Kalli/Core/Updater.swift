import Foundation
import Observation
import Sparkle

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

    /// `startingUpdater: true` startet die Hintergrundprüfung — die aber nur
    /// läuft, wenn der Nutzer sie erlaubt hat (siehe oben).
    ///
    /// Kein eigener Delegate: Jede Erweiterung hier wäre eine Stelle, an der
    /// man Sparkles Prüfungen versehentlich aufweicht. Der Standardweg ist der
    /// geprüfte Weg.
    private let controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

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
