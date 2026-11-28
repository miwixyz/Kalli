#if DEBUG
import AppKit
import EventKit
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
        steps.append(noPersonalData())
        steps.append(resources())
        steps.append(bundleSeal())
        steps.append(preferencesRoundTrip())
        steps.append(reminderParser())
        steps.append(zeiterfassung())
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

    /// Kein Kalender- und kein Erinnerungszugriff (K1) – drei unabhängige Messungen, jede allein reicht für FAIL:
    /// die Freigabe bei macOS (Rohwert; 3 = Vollzugriff, 4 = nur schreiben), die Sperre im Code
    /// (`CalendarStore.authorization`) und eine Probe mit frischem `EKEventStore`, die nur **zählt**, wie viele
    /// Kalender und Listen lesbar wären. Die Probe fragt nicht an (`calendars(for:)` löst keinen Dialog aus).
    private static func noPersonalData() -> Step {
        let raw = [EKEntityType.event, .reminder].map { EKEventStore.authorizationStatus(for: $0) }
        let granted = raw.contains { $0 == .fullAccess || $0 == .writeOnly }
        let gate = CalendarStore.authorization(for: .event) == .denied
            && CalendarStore.authorization(for: .reminder) == .denied
        let probe = EKEventStore()
        let visible = probe.calendars(for: .event).count + probe.calendars(for: .reminder).count
        let hint = granted ? " → Freigabe entziehen: tccutil reset Calendar|Reminders dev.mwlr.kalli.bild" : ""
        return Step(name: "Kein Datenzugriff", ok: !granted && gate && visible == 0,
                    detail: "macOS Kalender \(raw[0].rawValue), Erinnerungen \(raw[1].rawValue) (0 nie gefragt, "
                        + "2 abgelehnt, 3 Vollzugriff), Sperre im Code " + (gate ? "an" : "AUS")
                        + ", lesbare Kalender/Listen \(visible)" + hint)
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

    /// Zeiterfassung im echten Bündel: Ton im Bündel, Speicherort der Kopie nicht der echte Ordner, und ein
    /// Durchlauf Start → Pause → Weiter → Stopp in einer Wegwerf-Datei, danach mit neuer Instanz gelesen.
    private static func zeiterfassung() -> Step {
        let real = ZeitStore.standardURL().deletingLastPathComponent().lastPathComponent != "Kalli"
        let sound = ZeitSound.isAvailable
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("kalli-zeit-selftest-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("zeit.json")
        final class Clock: @unchecked Sendable { var now = Date() }
        let clock = Clock()
        let erfassung = ZeitErfassung(store: ZeitStore(url: url), now: { clock.now })
        erfassung.addProject(name: "Selbsttest")
        guard let id = erfassung.projects.first?.id else {
            return Step(name: "Zeiterfassung", ok: false, detail: "Projekt nicht angelegt")
        }
        erfassung.toggle(projectID: id)
        clock.now += 600; erfassung.pause()
        clock.now += 300; erfassung.resume()
        clock.now += 900
        let restored = ZeitErfassung(store: ZeitStore(url: url), now: { clock.now })
        let resumedOK = restored.zustand == .laeuft && Int(restored.elapsed(at: clock.now)) == 1500
        erfassung.stopByUser()
        let booked = ZeitErfassung(store: ZeitStore(url: url), now: { clock.now }).entries
        let netOK = booked.count == 1 && Int(booked[0].netDuration) == 1500 && Int(booked[0].grossDuration) == 1800
        let ok = real && sound && resumedOK && netOK
        return Step(name: "Zeiterfassung", ok: ok,
                    detail: "Ton " + (sound ? "da" : "FEHLT") + ", eigener Ordner " + (real ? "ja" : "NEIN")
                        + ", Wiederherstellen " + (resumedOK ? "ok" : "FALSCH") + ", gebucht netto "
                        + (booked.first.map { "\(Int($0.netDuration / 60)) min" } ?? "nichts"))
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
