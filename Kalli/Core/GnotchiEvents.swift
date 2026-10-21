import AppKit
import Darwin
import Foundation
import OSLog
import Security

/// Nächster Termin in Gnotchis Notch (Kalli 0.11.1, Gnotchi 0.5.0, Gnotchi SECURE-DESIGN G26).
///
/// Termin-Titel sind privat. Deshalb **nicht** über `DistributedNotificationCenter` (jeder lokale Prozess liest
/// mit), sondern über Gnotchis lokalen Socket `~/Library/Application Support/Gnotchi/kalli.sock`. Bevor ein Byte
/// rausgeht, prüft Kalli den Prozess am anderen Ende über sein Audit-Token gegen eine **Developer-ID**-Anforderung
/// für `dev.mwlr.gnotchi` (Team LTKJ6Z2VYB) und wartet auf Gnotchis `ok`; Gnotchi prüft Kalli genauso.
/// Gesendet werden nur Titel, Beginn und Kalenderfarbe des Termins, den Kallis Menüleiste ohnehin zeigt.
/// Zurück kommt nichts außer Gnotchis `ok`; ein Klick in der Notch öffnet Apple Kalender (Gnotchi selbst).
/// Nie Titel ins Protokoll.
enum GnotchiEvents {

    static let maxFrame = 4096
    static let ackTimeout: TimeInterval = 0.5
    /// Nach Gnotchis Start kurz warten, bis der Socket steht.
    static let launchDelay: TimeInterval = 3

    static let requirement =
        #"anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] and "#
        + #"certificate leaf[field.1.2.840.113635.100.6.1.13] and identifier "dev.mwlr.gnotchi" and "#
        + #"certificate leaf[subject.OU] = "LTKJ6Z2VYB""#
    static let gnotchiBundleID = "dev.mwlr.gnotchi"

    static var socketPath: String? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Gnotchi/kalli.sock").path
    }

    // MARK: Reine Teile (getestet)

    /// `{"v":1,"event":{…}}` bzw. `{"v":1,"event":null}`. Nur echte Termine mit Uhrzeit, keine Erinnerungen,
    /// keine ganztägigen (Kallis `nextEvent` liefert ohnehin nur solche).
    static func payload(_ item: AgendaItem?) -> [String: Any] {
        guard let item, case .event = item.kind, !item.isAllDay, let start = item.start else {
            return ["v": 1, "event": NSNull()]
        }
        return ["v": 1, "event": ["title": item.title, "start": start.timeIntervalSince1970.rounded(),
                                  "color": hex(item.color)]]
    }

    static func hex(_ c: RGBA) -> String {
        func byte(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", byte(c.r), byte(c.g), byte(c.b))
    }

    /// 4 Byte Länge (Big Endian) + JSON.
    static func frame(_ object: [String: Any]) -> Data? {
        guard let json = try? JSONSerialization.data(withJSONObject: object), json.count + 4 <= maxFrame else { return nil }
        let n = UInt32(json.count).bigEndian
        return withUnsafeBytes(of: n) { Data($0) } + json
    }

    enum Frame { case message([String: Any]?), needMore, invalid }

    /// Nimmt die nächste vollständige Nachricht vorne aus `buffer` (`nil`-Objekt = kein JSON-Objekt).
    static func nextFrame(_ buffer: inout Data) -> Frame {
        guard buffer.count >= 4 else { return .needMore }
        let b = [UInt8](buffer.prefix(4))
        let length = Int(b[0]) << 24 | Int(b[1]) << 16 | Int(b[2]) << 8 | Int(b[3])
        guard length > 0, length + 4 <= maxFrame else { return .invalid }
        guard buffer.count >= length + 4 else { return .needMore }
        let payload = Data(buffer.dropFirst(4).prefix(length))
        buffer = Data(buffer.dropFirst(4 + length))
        return .message(try? JSONSerialization.jsonObject(with: payload) as? [String: Any])
    }

    /// `v` Zahl 1 (kein Wahrheitswert).
    static func isVersion1(_ obj: [String: Any]?) -> Bool {
        guard let v = obj?["v"] as? NSNumber, CFGetTypeID(v) != CFBooleanGetTypeID() else { return false }
        return v.intValue == 1 && v.doubleValue == 1
    }

    static func isAck(_ obj: [String: Any]?) -> Bool { isVersion1(obj) && (obj?["ok"] as? Bool) == true }
}

/// Hält höchstens eine geprüfte Verbindung zu Gnotchi und meldet den nächsten Termin bei jeder Änderung.
/// Verbindet beim Start, 3 s nach Gnotchis Start und bei jeder Änderung, falls nicht verbunden. Fehlt Gnotchi
/// (kein Socket, alte Version, Schalter aus) → nichts, kein Fehler.
@MainActor
final class GnotchiEventSender {

    private static let log = Logger(subsystem: "com.kalli.app", category: "gnotchi")

    private let current: @MainActor () -> AgendaItem?
    private let path: String?
    private let requirement: String
    private var fd: Int32 = -1
    private var source: DispatchSourceRead?
    private var launchObserver: NSObjectProtocol?

    /// `current`: Kallis nächster Termin (beobachtet). `path`/`requirement` nur im Test anders.
    init(current: @escaping @MainActor () -> AgendaItem?,
         path: String? = GnotchiEvents.socketPath, requirement: String = GnotchiEvents.requirement) {
        self.current = current
        self.path = path
        self.requirement = requirement
    }

    func start() {
        launchObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let id = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            guard id == GnotchiEvents.gnotchiBundleID else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + GnotchiEvents.launchDelay) {
                MainActor.assumeIsolated { self?.sendCurrent() }
            }
        }
        observe()
        sendCurrent()
    }

    var isConnected: Bool { fd >= 0 }

    /// Beobachtet Kallis nächsten Termin; `withObservationTracking` meldet nur die erste Änderung → neu anmelden.
    private func observe() {
        withObservationTracking { _ = current() } onChange: { [weak self] in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.sendCurrent()
                    self?.observe()
                }
            }
        }
    }

    /// Aktuellen Stand senden; ohne Verbindung erst verbinden (dann geht er gleich nach dem `ok` raus).
    func sendCurrent() {
        if fd < 0 { connect() }
        guard fd >= 0, let data = GnotchiEvents.frame(GnotchiEvents.payload(current())) else { return }
        let n = data.withUnsafeBytes { write(fd, $0.baseAddress, data.count) }
        if n != data.count { close(reason: "Schreibfehler") }
    }

    private func connect() {
        guard let path else { return }
        var addr = sockaddr_un()
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return }
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: bytes + [0]) }
        let s = socket(AF_UNIX, SOCK_STREAM, 0)
        guard s >= 0 else { return }
        var one: Int32 = 1
        setsockopt(s, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let connected = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(s, $0, len) } }
        guard connected == 0 else { Darwin.close(s); return }   // kein Gnotchi: still
        guard Self.serverPasses(s, requirement) else {
            Darwin.close(s)
            return Self.log.error("Termine: Gegenseite ist kein echtes Gnotchi – nichts gesendet")
        }
        guard readAck(s) else {
            Darwin.close(s)
            return Self.log.notice("Termine: Gnotchi hat nicht bestätigt")
        }
        _ = fcntl(s, F_SETFL, fcntl(s, F_GETFL) | O_NONBLOCK)
        fd = s
        let src = DispatchSource.makeReadSource(fileDescriptor: s, queue: .main)
        src.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.readIncoming() } }
        src.resume()
        source = src
        Self.log.notice("Termine: mit Gnotchi verbunden")
    }

    /// Audit-Token des lauschenden Prozesses → Code → Anforderung (Audit-Token statt PID: kein Wettlauf).
    static func serverPasses(_ fd: Int32, _ requirement: String) -> Bool {
        var token = audit_token_t()
        var len = socklen_t(MemoryLayout<audit_token_t>.size)
        guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &len) == 0 else { return false }
        let data = withUnsafeBytes(of: &token) { Data($0) }
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributeAudit: data] as CFDictionary, [], &code) == errSecSuccess,
              let code else { return false }
        var req: SecRequirement?
        guard SecRequirementCreateWithString(requirement as CFString, [], &req) == errSecSuccess, let req else { return false }
        return SecCodeCheckValidity(code, [], req) == errSecSuccess
    }

    private func readAck(_ s: Int32) -> Bool {
        var tv = timeval(tv_sec: 0, tv_usec: Int32(GnotchiEvents.ackTimeout * 1_000_000))
        setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        var buf = Data()
        var chunk = [UInt8](repeating: 0, count: 256)
        while true {
            let n = read(s, &chunk, chunk.count)
            guard n > 0 else { return false }
            buf.append(contentsOf: chunk[0..<n])
            switch GnotchiEvents.nextFrame(&buf) {
            case .needMore: continue
            case .invalid: return false
            case .message(let obj): return GnotchiEvents.isAck(obj)
            }
        }
    }

    /// Gnotchi schickt nach dem `ok` nichts mehr; gelesen wird nur, um eine Trennung zu bemerken.
    private func readIncoming() {
        var chunk = [UInt8](repeating: 0, count: 512)
        let n = read(fd, &chunk, chunk.count)
        if n == 0 { return close(reason: "Gnotchi getrennt") }
        if n < 0, errno != EAGAIN { close(reason: "Lesefehler") }
    }

    private func close(reason: String) {
        source?.cancel()
        source = nil
        if fd >= 0 { Darwin.close(fd); fd = -1 }
        Self.log.notice("Termine: \(reason, privacy: .public)")
    }
}
