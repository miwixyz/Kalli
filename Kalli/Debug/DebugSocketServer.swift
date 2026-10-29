#if DEBUG
import Darwin
import Foundation
import OSLog
import Security

/// Lokaler Socket des Befehlskanals (docs/SECURE-DESIGN.md K1) – schlanke Übertragung von Gnotchis
/// `PeerSocketServer` (G21/G45): ein Client, jede Nachricht zählt, höchstens 10 je Sekunde.
///
/// Alles auf einer eigenen seriellen Warteschlange; nach außen nur `onCommand` mit geprüften Befehlen. Jede
/// Verbindung wird **vor dem ersten gelesenen Byte** über das Audit-Token der Gegenseite gegen `requirement`
/// geprüft. Ungültige Rahmen oder Befehle: Verbindung zu, keine Antwort. Nie Inhalte ins Protokoll.
final class DebugSocketServer: @unchecked Sendable {

    enum StartError: Error, Equatable {
        case directory, staleFile, pathTooLong, socket(Int32)
    }

    static let maxPerSecond = 10
    private static let log = Logger(subsystem: "com.kalli.app", category: "debug")

    let socketPath: String
    private let requirement: SecRequirement
    private let onCommand: @Sendable (DebugCommand) -> Void
    private let queue = DispatchQueue(label: "dev.mwlr.kalli.debug.socket")

    // Nur auf `queue`:
    private var listenFD: Int32 = -1
    private var listenSource: DispatchSourceRead?
    private var clientFD: Int32 = -1
    private var clientSource: DispatchSourceRead?
    private var buffer = Data()
    private var windowStart = Date.distantPast
    private var windowCount = 0

    init(socketPath: String, requirement: SecRequirement, onCommand: @escaping @Sendable (DebugCommand) -> Void) {
        self.socketPath = socketPath
        self.requirement = requirement
        self.onCommand = onCommand
    }

    // MARK: Dateisystem

    /// Ordner anlegen bzw. prüfen: echter Ordner (kein Link), gehört uns, Rechte 0700.
    static func prepareDirectory(_ url: URL) -> Bool {
        let path = url.path
        var st = stat()
        if lstat(path, &st) != 0 {
            guard errno == ENOENT, mkdir(path, 0o700) == 0, lstat(path, &st) == 0 else { return false }
        }
        guard (st.st_mode & S_IFMT) == S_IFDIR, st.st_uid == getuid() else { return false }
        return chmod(path, 0o700) == 0
    }

    /// Alte Socket-Datei entfernen – nur, wenn es wirklich ein Socket ist und uns gehört. Sonst scheitert der Start.
    private static func removeStaleSocket(_ path: String) -> Bool {
        var st = stat()
        guard lstat(path, &st) == 0 else { return errno == ENOENT }
        guard (st.st_mode & S_IFMT) == S_IFSOCK, st.st_uid == getuid() else { return false }
        return unlink(path) == 0
    }

    // MARK: Start

    func start() throws(StartError) {
        guard Self.prepareDirectory(URL(fileURLWithPath: socketPath).deletingLastPathComponent()) else { throw .directory }
        guard Self.removeStaleSocket(socketPath) else { throw .staleFile }
        var addr = sockaddr_un()
        let bytes = Array(socketPath.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { throw .pathTooLong }
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: bytes + [0]) }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw .socket(errno) }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bound = withUnsafePointer(to: &addr) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, len) } }
        guard bound == 0, chmod(socketPath, 0o600) == 0, listen(fd, 2) == 0 else {
            let e = errno
            close(fd)
            unlink(socketPath)
            throw .socket(e)
        }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        queue.sync {
            listenFD = fd
            let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            src.setEventHandler { [weak self] in self?.acceptPending() }
            src.resume()
            listenSource = src
        }
    }

    // MARK: Verbindungen (auf queue)

    private func acceptPending() {
        while true {
            let fd = accept(listenFD, nil, nil)
            guard fd >= 0 else { return }
            var one: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
            let status = Self.checkPeer(fd, requirement)
            guard status == errSecSuccess else {
                close(fd)
                Self.log.error("Befehlskanal: Verbindung abgelehnt (OSStatus \(status, privacy: .public))")
                continue
            }
            // Eine geprüfte neue Verbindung ersetzt die alte.
            closeClient(reason: nil)
            _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
            clientFD = fd
            buffer = Data()
            if let ack = DebugCommand.frame(["v": 1, "ok": true]) {
                _ = ack.withUnsafeBytes { write(fd, $0.baseAddress, ack.count) }
            }
            let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
            src.setEventHandler { [weak self] in self?.readClient() }
            src.resume()
            clientSource = src
        }
    }

    /// Audit-Token der Gegenseite → Code → Anforderung. Audit-Token statt PID: kein Wettlauf mit wiederverwendeten
    /// Prozessnummern.
    private static func checkPeer(_ fd: Int32, _ requirement: SecRequirement) -> OSStatus {
        var token = audit_token_t()
        var len = socklen_t(MemoryLayout<audit_token_t>.size)
        guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &len) == 0 else { return errSecCSGuestInvalid }
        let data = withUnsafeBytes(of: &token) { Data($0) }
        var code: SecCode?
        let st = SecCodeCopyGuestWithAttributes(nil, [kSecGuestAttributeAudit: data] as CFDictionary, [], &code)
        guard st == errSecSuccess, let code else { return st == errSecSuccess ? errSecCSGuestInvalid : st }
        return SecCodeCheckValidity(code, [], requirement)
    }

    private func readClient() {
        var chunk = [UInt8](repeating: 0, count: DebugCommand.maxFrame)
        let n = read(clientFD, &chunk, chunk.count)
        if n == 0 { return closeClient(reason: nil) }
        if n < 0 { return errno == EAGAIN ? () : closeClient(reason: "Lesefehler") }
        buffer.append(contentsOf: chunk[0..<n])
        while true {
            switch DebugCommand.nextFrame(&buffer) {
            case .needMore:
                return
            case .invalid:
                return closeClient(reason: "ungültiger Rahmen")
            case .message(let payload):
                guard let command = DebugCommand.parse(payload) else { return closeClient(reason: "ungültiger Befehl") }
                deliver(command)
            }
        }
    }

    private func closeClient(reason: String?) {
        clientSource?.cancel()
        clientSource = nil
        if clientFD >= 0 { close(clientFD); clientFD = -1 }
        buffer = Data()
        if let reason { Self.log.notice("Befehlskanal: \(reason, privacy: .public)") }
    }

    /// Höchstens `maxPerSecond` Befehle je Sekunde; der Rest fällt weg.
    private func deliver(_ command: DebugCommand) {
        let now = Date()
        if now.timeIntervalSince(windowStart) >= 1 { windowStart = now; windowCount = 0 }
        windowCount += 1
        if windowCount <= Self.maxPerSecond { onCommand(command) }
    }
}
#endif
