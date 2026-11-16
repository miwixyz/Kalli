#if DEBUG
import AppKit
import Foundation

/// Selbsttest der Bild-Testkopie (Muster aus Gnotchi und Tippi, BAMA `test-mac-app`; Kalli 2026-11-16): ruft im
/// laufenden Bündel dieselben Teile auf wie die Oberfläche und meldet je Schritt PASS oder FAIL. Kommt als Befehl
/// `selftest` über den Befehlskanal (`kallictl selftest`, Exit 0/1) – Kalli ist eine Ein-Instanz-Menüleisten-App.
///
/// Abgeschottet wie die ganze Kopie (K1): eigener Datenordner, Einstellungen nur in einer Wegwerf-Suite, kein
/// Kalender- und Erinnerungszugriff, keine Mitteilungen (die Wegwerf-`CalendarStore` bekommt `alerts: nil`), keine
/// Verbindung zu Gnotchi, kein Dienste-Menü, kein Updater. Typ und Antwort-Aufbau: `SelfTestResult.swift`.
extension SelfTest {
    private static let scratchSuite = "dev.mwlr.kalli.bild.selftest"
    /// Dauer des Rauchtests in Sekunden (Kurzfassung für den Befehl, Wartezeit der Steuerung 30 s).
    static let smokeSeconds = 3.0

    static func run(windowFor: (String) -> NSWindow?) async -> [Step] {
        var steps: [Step] = []
        steps.append(isolation())
        steps.append(resources())
        steps.append(bundleSeal())
        steps.append(preferencesRoundTrip())
        steps.append(reminderParser())
        steps.append(contentsOf: await windows(windowFor))
        steps.append(await observerSmoke())
        return steps
    }

    // MARK: Schritte

    /// Die Kopie darf nie auf Michaels echte Daten zeigen.
    private static func isolation() -> Step {
        let id = Bundle.main.bundleIdentifier ?? "?"
        let folder = DebugBridge.directory?.lastPathComponent ?? "?"
        let ok = id == "dev.mwlr.kalli.bild" && BildKopie.isActive && folder == "Kalli Bild"
        return Step(name: "Abschottung", ok: ok, detail: "Kennung \(id), Datenordner \(folder)")
    }

    /// Schrift und Texte im Bündel – fehlt eine, fällt die Oberfläche still auf die Systemschrift zurück.
    private static func resources() -> Step {
        let font = NSFontManager.shared.availableMembers(ofFontFamily: FamilyTheme.fontFamily) != nil
        let names: [String] = ["HILFE", "CHANGELOG", "RECHTLICHES", "THIRD-PARTY-LICENSES"]
        let missing: [String] = names.filter { Bundle.main.url(forResource: $0, withExtension: "md") == nil }
        let fontText = font ? "da" : "FEHLT"
        let missingText = missing.isEmpty ? "" : ", fehlt: " + missing.joined(separator: ", ")
        return Step(name: "Ressourcen", ok: font && missing.isEmpty, detail: "Schrift " + fontText + missingText)
    }

    /// Siegel unversehrt (die Kopie trägt eine andere Kennung als das echte Kalli, deshalb ohne Team-Anforderung).
    private static func bundleSeal() -> Step {
        var code: SecStaticCode?
        var status = SecStaticCodeCreateWithPath(Bundle.main.bundleURL as CFURL, [], &code)
        if status == errSecSuccess, let code {
            let flags = SecCSFlags(rawValue: kSecCSCheckNestedCode | kSecCSStrictValidate | kSecCSCheckAllArchitectures)
            status = SecStaticCodeCheckValidity(code, flags, nil)
        }
        return Step(name: "Bundle-Siegel", ok: status == errSecSuccess, detail: "OSStatus \(status)")
    }

    /// Einstellung schreiben, mit neuer Instanz lesen – in einer Wegwerf-Suite, nie in den echten Einstellungen.
    private static func preferencesRoundTrip() -> Step {
        guard let suite = UserDefaults(suiteName: scratchSuite) else {
            return Step(name: "Einstellungen", ok: false, detail: "Suite nicht angelegt")
        }
        suite.removePersistentDomain(forName: scratchSuite)
        defer { suite.removePersistentDomain(forName: scratchSuite) }
        let before = Preferences(defaults: suite).showWeekNumbers   // Werkseinstellung: an
        Preferences(defaults: suite).showWeekNumbers = !before
        let after = Preferences(defaults: suite).showWeekNumbers
        return Step(name: "Einstellungen", ok: after == !before, detail: "Kalenderwochen \(before) → \(after)")
    }

    /// Texterkennung der Schnell-Erinnerung im echten Bündel: Tag und Uhrzeit raus, Titel bleibt.
    private static func reminderParser() -> Step {
        let cal = Calendar(identifier: .gregorian)
        let now = cal.date(from: DateComponents(year: 2026, month: 11, day: 16, hour: 10)) ?? Date()
        let parsed = QuickReminder.parse("Zahnarzt anrufen morgen 15 Uhr", now: now, calendar: cal)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: now))
        let dayOK = parsed.day.map { cal.startOfDay(for: $0) } == tomorrow
        let ok = parsed.title == "Zahnarzt anrufen" && dayOK && parsed.time == QuickReminder.Time(hour: 15, minute: 0)
        return Step(name: "Erinnerungs-Erkennung", ok: ok,
                    detail: "Titel „\(parsed.title)“, morgen " + (dayOK ? "erkannt" : "NICHT erkannt")
                        + ", Zeit " + (parsed.time == QuickReminder.Time(hour: 15, minute: 0) ? "15:00" : "FALSCH"))
    }

    /// Einstellungen und Hilfe öffnen sich wirklich (sichtbar mit ihrer Kennung). Danach wieder zu.
    private static func windows(_ windowFor: (String) -> NSWindow?) async -> [Step] {
        var result: [Step] = []
        for id in [DebugCommand.settingsWindow, DebugCommand.helpWindow] {
            guard let win = windowFor(id) else {
                result.append(Step(name: "Fenster \(id)", ok: false, detail: "nicht gebaut"))
                continue
            }
            win.makeKeyAndOrderFront(nil)
            for _ in 0..<15 where !win.isVisible { try? await Task.sleep(for: .milliseconds(100)) }
            result.append(Step(name: "Fenster \(id)", ok: win.isVisible,
                               detail: "\(Int(win.frame.width))×\(Int(win.frame.height))"))
            win.close()
        }
        return result
    }

    /// Rauchtest der Beobachter: eine Wegwerf-`CalendarStore` (ohne Mitteilungen, ohne Berechtigung) meldet sich für
    /// Aufwachen und Tageswechsel an; beide Meldungen kommen mehrfach, die Rückrufe laufen auf der Hauptschlange
    /// (genau der Ort der „Hauptthread ≠ MainActor“-Falle, siehe `CalendarStore.init`). Ohne Zeitraum tut `reload()`
    /// nichts – es geht um Abstürze, nicht um Termine. Ein Absturz beendet die Kopie: dann fehlt die Antwort.
    private static func observerSmoke() async -> Step {
        guard let suite = UserDefaults(suiteName: scratchSuite) else {
            return Step(name: "Beobachter-Rauchtest", ok: false, detail: "Suite nicht angelegt")
        }
        suite.removePersistentDomain(forName: scratchSuite)
        defer { suite.removePersistentDomain(forName: scratchSuite) }
        let store = CalendarStore(prefs: Preferences(defaults: suite), alerts: nil)
        defer { store.stop() }
        let rounds = 6
        for _ in 0..<rounds {
            NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.didWakeNotification, object: nil)
            NotificationCenter.default.post(name: .NSCalendarDayChanged, object: nil)
            try? await Task.sleep(for: .seconds(smokeSeconds / Double(rounds)))
        }
        return Step(name: "Beobachter-Rauchtest", ok: true,
                    detail: "Aufwachen und Tageswechsel \(rounds)× in \(smokeSeconds) s, kein Absturz")
    }
}
#endif
