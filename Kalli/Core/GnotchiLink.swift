import AppKit
import Foundation
import OSLog
import Security

/// Gnotchi – die Notch-App der Familie (github.com/miwixyz/Gnotchi) – zeigt ab 0.4.0 bereite Updates der
/// Familien-Apps als Live-Aktivität (Gnotchi SECURE-DESIGN G23/G24). Kalli ist der erste Sender.
///
/// Weg: `DistributedNotificationCenter`. **Jeder lokale Prozess kann mitlesen und senden.** Deshalb geht nur
/// raus, was ohnehin öffentlich ist: App-Kürzel und Versionsnummer. Gesendet wird nur, wenn ein
/// Developer-ID-signiertes Gnotchi ≥ 0.4.0 läuft und dort „Updates der App-Familie“ nicht aus ist.
///
/// Zurück kommt nur `app.mwlr.familie.update.show` („zeig dein Update-Fenster“), nachdem jemand in Gnotchi auf
/// das Update geklickt hat. Kalli reagiert darauf **nur, wenn es selbst ein Update bereit hat**, und zeigt dann
/// Sparkles eigenes Fenster – eine Fälschung kann also höchstens das echte Update-Fenster öffnen. Kein anderer
/// Befehl, kein Text aus der Meldung wird verwendet.
enum GnotchiLink {

    static let updateName = Notification.Name("app.mwlr.familie.update")
    static let showName = Notification.Name("app.mwlr.familie.update.show")
    static let app = "kalli"
    static let gnotchiBundleID = "dev.mwlr.gnotchi"
    static let requirement =
        #"anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] and "#
        + #"certificate leaf[field.1.2.840.113635.100.6.1.13] and identifier "dev.mwlr.gnotchi" and "#
        + #"certificate leaf[subject.OU] = "LTKJ6Z2VYB""#
    static let minimumVersion = [0, 4, 0]
    /// Gnotchis Schalter „Updates der App-Familie“ (CFPreferences, Domäne dev.mwlr.gnotchi).
    static let settingKey = "familyUpdates"

    // MARK: Reine Teile (getestet)

    /// `{"v":1, "app":"kalli", "version":"0.11.0", "ready":true}`. Version nur in der Form, die Gnotchi annimmt
    /// (1.2 oder 1.2.3, je höchstens drei Ziffern) – sonst `nil`, dann geht nichts raus.
    static func payload(version: String, ready: Bool) -> [String: Any]? {
        guard isValidVersion(version) else { return nil }
        return ["v": 1, "app": app, "version": version, "ready": ready]
    }

    static func isValidVersion(_ s: String) -> Bool {
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count) else { return false }
        return parts.allSatisfy { p in
            (1...3).contains(p.count) && p.unicodeScalars.allSatisfy { ("0"..."9").contains($0) }
        }
    }

    /// Ist die Anfrage „zeig dein Update-Fenster“ an Kalli gerichtet? `v` Zahl 1 (kein Wahrheitswert), `app` = kalli.
    static func isShowRequest(_ info: [AnyHashable: Any]?) -> Bool {
        guard let info, let v = info["v"] as? NSNumber, CFGetTypeID(v) != CFBooleanGetTypeID(),
              v.intValue == 1, v.doubleValue == 1 else { return false }
        return info["app"] as? String == app
    }

    static func versionSupported(_ version: String?) -> Bool {
        guard let version else { return false }
        let parts = version.split(separator: ".").map { Int($0) }
        guard !parts.isEmpty, !parts.contains(where: { $0 == nil }) else { return false }
        let nums = parts.compactMap { $0 }
        for i in 0..<max(nums.count, minimumVersion.count) {
            let a = i < nums.count ? nums[i] : 0
            let b = i < minimumVersion.count ? minimumVersion[i] : 0
            if a != b { return a > b }
        }
        return true
    }

    /// Fehlender Schlüssel = Gnotchis Werkseinstellung (an). Nur ein ausdrückliches `false` schaltet ab.
    static func settingAllows(_ value: Any?) -> Bool {
        (value as? Bool) ?? true
    }

    /// Was beim Wechsel von `old` nach `new` (Sparkles „bereites Update“) zu senden ist: neues/anderes Update →
    /// bereit; Update weg → erledigt (mit der alten Version); sonst nichts.
    static func message(old: String?, new: String?) -> [String: Any]? {
        if let new, new != old { return payload(version: new, ready: true) }
        if new == nil, let old { return payload(version: old, ready: false) }
        return nil
    }

    // MARK: System

    /// Läuft ein echtes Gnotchi, das Updates der Familie zeigen will? Signatur über die PID geprüft, nicht der
    /// Bundle-ID geglaubt (wie Qotti).
    @MainActor
    static func gnotchiListens() -> Bool {
        guard let gnotchi = NSRunningApplication.runningApplications(withBundleIdentifier: gnotchiBundleID)
            .first(where: { !$0.isTerminated }) else { return false }
        let version = gnotchi.bundleURL
            .flatMap { NSDictionary(contentsOf: $0.appending(path: "Contents/Info.plist")) }?["CFBundleShortVersionString"] as? String
        guard versionSupported(version), isSigned(pid: gnotchi.processIdentifier) else { return false }
        return settingAllows(CFPreferencesCopyAppValue(settingKey as CFString, gnotchiBundleID as CFString))
    }

    private static func isSigned(pid: pid_t) -> Bool {
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributePid: pid] as CFDictionary, [], &code) == errSecSuccess,
              let code else { return false }
        var req: SecRequirement?
        guard SecRequirementCreateWithString(requirement as CFString, [], &req) == errSecSuccess, let req else { return false }
        return SecCodeCheckValidity(code, [], req) == errSecSuccess
    }
}

/// Meldet Gnotchi Kallis bereites Update und hört auf „zeig dein Update-Fenster“.
@MainActor
final class GnotchiUpdateSender {

    private static let log = Logger(subsystem: "com.kalli.app", category: "gnotchi")
    /// Nach Gnotchis Start kurz warten, bis es seinen Beobachter angemeldet hat.
    private static let resendDelay: TimeInterval = 3

    /// Zuletzt gemeldete Version (nil = nichts bereit).
    private(set) var current: String?
    private let hasUpdate: @MainActor () -> Bool
    private let showUpdate: @MainActor () -> Void
    /// Beobachter leben so lange wie die App (der Sender hängt am Updater, den es einmal gibt).
    private var tokens: [(NotificationCenter, NSObjectProtocol)] = []
    private var launchWatcher: GnotchiLaunchWatcher?

    /// `hasUpdate`: ob Kalli gerade selbst ein Update bereit hat. `showUpdate`: Sparkles Fenster zeigen.
    init(hasUpdate: @escaping @MainActor () -> Bool, showUpdate: @escaping @MainActor () -> Void) {
        self.hasUpdate = hasUpdate
        self.showUpdate = showUpdate
        let dnc = DistributedNotificationCenter.default()
        tokens.append((dnc, dnc.addObserver(forName: GnotchiLink.showName, object: nil, queue: .main) { [weak self] note in
            let forKalli = GnotchiLink.isShowRequest(note.userInfo)
            MainActor.assumeIsolated { if forKalli { self?.showRequested() } }
        }))
        // Gnotchi speichert keine Meldungen: Startet es (neu), meldet Kalli sein bereites Update noch einmal.
        launchWatcher = GnotchiLaunchWatcher(delay: Self.resendDelay) { [weak self] in self?.resend() }
    }

    /// Sparkles „bereites Update“ hat sich geändert.
    func update(_ version: String?) {
        let message = GnotchiLink.message(old: current, new: version)
        current = version
        if let message { post(message) }
    }

    private func resend() {
        guard let current, let message = GnotchiLink.payload(version: current, ready: true) else { return }
        post(message)
    }

    private func showRequested() {
        guard hasUpdate() else {
            Self.log.notice("Gnotchi bittet um das Update-Fenster – kein Update bereit, ignoriert")
            return
        }
        Self.log.notice("Gnotchi bittet um das Update-Fenster – zeige es")
        showUpdate()
    }

    private func post(_ message: [String: Any]) {
        guard GnotchiLink.gnotchiListens() else { return }
        DistributedNotificationCenter.default().postNotificationName(
            GnotchiLink.updateName, object: nil, userInfo: message, deliverImmediately: true)
        Self.log.notice("Update an Gnotchi gemeldet (\((message["ready"] as? Bool) == true ? "bereit" : "erledigt", privacy: .public))")
    }
}

/// Meldet Gnotchis Start. **Nicht** über `didLaunchApplicationNotification`: macOS schickt sie für Apps ohne
/// Dock-Symbol (Gnotchi) nicht – gemessen 21.10.: 0 Meldungen, Beobachtung von `runningApplications` 1.
@MainActor
final class GnotchiLaunchWatcher {
    private var observation: NSKeyValueObservation?

    init(delay: TimeInterval, onLaunch: @escaping @MainActor () -> Void) {
        observation = NSWorkspace.shared.observe(\.runningApplications, options: [.new]) { _, change in
            guard change.newValue?.contains(where: { $0.bundleIdentifier == GnotchiLink.gnotchiBundleID }) == true else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                MainActor.assumeIsolated { onLaunch() }
            }
        }
    }
}
