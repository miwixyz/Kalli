import Darwin
import Security
import XCTest

// SYNTHETISCH – erfundene Termine, keine echten Kalenderdaten.

/// 0.12.0 Nächster Termin an Gnotchi (Gnotchi SECURE-DESIGN G26): Nachricht, Rahmen, Prüfung der Gegenseite.
@MainActor
final class GnotchiEventsTests: XCTestCase {

    private func item(_ kind: AgendaItem.Kind = .event, allDay: Bool = false,
                      start: Date? = Date(timeIntervalSince1970: 1_800_000_000)) -> AgendaItem {
        AgendaItem(id: "1", title: "Zahnarzt", start: start, end: start?.addingTimeInterval(1800), isAllDay: allDay,
                   hasTime: true, kind: kind, sourceID: "k", color: RGBA(r: 1, g: 0.5, b: 0, a: 1), hasAlarms: false)
    }

    // MARK: Nachricht

    func testPayloadForEvent() {
        let p = GnotchiEvents.payload(item())
        let e = p["event"] as? [String: Any]
        XCTAssertEqual(p["v"] as? Int, 1)
        XCTAssertEqual(e?["title"] as? String, "Zahnarzt")
        XCTAssertEqual(e?["start"] as? Double, 1_800_000_000)
        XCTAssertEqual(e?["color"] as? String, "#FF8000")
        XCTAssertEqual(Set(e?.keys.map { $0 } ?? []), ["title", "start", "color"], "nur Titel, Beginn, Farbe")
    }

    func testPayloadNullForNothingAllDayOrReminder() {
        XCTAssertTrue(GnotchiEvents.payload(nil)["event"] is NSNull)
        XCTAssertTrue(GnotchiEvents.payload(item(allDay: true))["event"] is NSNull)
        XCTAssertTrue(GnotchiEvents.payload(item(.reminder(completed: false)))["event"] is NSNull)
        XCTAssertTrue(GnotchiEvents.payload(item(start: nil))["event"] is NSNull)
    }

    func testLongTitleIsCutSoTheFrameStillFits() throws {
        let long = AgendaItem(id: "1", title: String(repeating: "Ä", count: 5000), start: Date(), end: nil, isAllDay: false,
                              hasTime: true, kind: .event, sourceID: "k", color: .fallback, hasAlarms: false)
        let p = GnotchiEvents.payload(long)
        XCTAssertEqual(((p["event"] as? [String: Any])?["title"] as? String)?.count, GnotchiEvents.maxTitle)
        XCTAssertNotNil(GnotchiEvents.frame(p), "Nachricht passt in den Rahmen")
    }

    func testHexClamps() {
        XCTAssertEqual(GnotchiEvents.hex(RGBA(r: 2, g: -1, b: 0.2, a: 1)), "#FF0033")
    }

    func testAckNeedsNumericVersion() {
        XCTAssertTrue(GnotchiEvents.isAck(["v": 1, "ok": true]))
        XCTAssertFalse(GnotchiEvents.isAck(["v": true, "ok": true]), "v als Bool")
        XCTAssertFalse(GnotchiEvents.isAck(["v": 2, "ok": true]))
    }

    func testFrameRoundTrip() throws {
        var buf = try XCTUnwrap(GnotchiEvents.frame(["v": 1, "ok": true]))
        buf.append(contentsOf: [0, 0])   // Anfang des nächsten Rahmens
        guard case .message(let obj) = GnotchiEvents.nextFrame(&buf) else { return XCTFail("kein Rahmen") }
        XCTAssertTrue(GnotchiEvents.isAck(obj))
        guard case .needMore = GnotchiEvents.nextFrame(&buf) else { return XCTFail("Rest unvollständig") }
        var bad = Data([0, 0, 0x20, 0])   // 8 KB angekündigt
        guard case .invalid = GnotchiEvents.nextFrame(&bad) else { return XCTFail("zu groß") }
    }

    // MARK: Prüfung der Gegenseite (echter Socket)

    func testSendsOnlyToVerifiedServer() throws {
        let server = try TestServer()
        defer { server.stop() }
        let it = item()
        // Gegenprobe: Gnotchis Anforderung – der Testlauf ist kein Gnotchi → keine Nachricht.
        let refused = GnotchiEventSender(current: { it }, path: server.path)
        refused.sendCurrent()
        XCTAssertFalse(refused.isConnected)
        XCTAssertEqual(server.receivedAfterAck(timeout: 0.5), 0, "nichts an einen fremden Server")

        // Mit der eigenen Anforderung (Testlauf = Server) geht der Termin raus.
        let accepted = GnotchiEventSender(current: { it }, path: server.path,
                                          requirement: try selfRequirement())
        accepted.sendCurrent()
        XCTAssertTrue(accepted.isConnected)
        XCTAssertGreaterThan(server.receivedAfterAck(timeout: 2), 0)
    }

    private func selfRequirement() throws -> String {
        var me: SecCode?
        XCTAssertEqual(SecCodeCopySelf([], &me), errSecSuccess)
        var stat: SecStaticCode?
        XCTAssertEqual(SecCodeCopyStaticCode(try XCTUnwrap(me), [], &stat), errSecSuccess)
        var req: SecRequirement?
        XCTAssertEqual(SecCodeCopyDesignatedRequirement(try XCTUnwrap(stat), [], &req), errSecSuccess)
        var text: CFString?
        XCTAssertEqual(SecRequirementCopyString(try XCTUnwrap(req), [], &text), errSecSuccess)
        return try XCTUnwrap(text) as String
    }
}

/// Minimaler Server auf eigenem Thread: nimmt Verbindungen an, schickt `ok`, zählt danach empfangene Bytes.
private final class TestServer: @unchecked Sendable {
    let path = "/tmp/kgt-\(UUID().uuidString.prefix(8)).sock"
    private let fd: Int32
    private let lock = NSLock()
    private var bytes = 0

    init() throws {
        fd = socket(AF_UNIX, SOCK_STREAM, 0)
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { $0.copyBytes(from: Array(path.utf8) + [0]) }
        let r = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard r == 0, listen(fd, 4) == 0 else { throw POSIXError(.EADDRINUSE) }
        Thread.detachNewThread { [self] in serve() }
    }

    private func serve() {
        while true {
            let c = accept(fd, nil, nil)
            guard c >= 0 else { return }   // Server zu
            if let ack = GnotchiEvents.frame(["v": 1, "ok": true]) { _ = ack.withUnsafeBytes { write(c, $0.baseAddress, ack.count) } }
            var chunk = [UInt8](repeating: 0, count: 1024)
            while true {
                let n = read(c, &chunk, chunk.count)
                guard n > 0 else { break }
                lock.lock(); bytes += n; lock.unlock()
            }
            close(c)
        }
    }

    /// Bytes, die nach dem `ok` ankamen (wartet höchstens `timeout`, bis etwas da ist).
    func receivedAfterAck(timeout: TimeInterval) -> Int {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            lock.lock(); let b = bytes; lock.unlock()
            if b > 0 { return b }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        lock.lock(); defer { lock.unlock() }
        return bytes
    }

    func stop() {
        close(fd)
        unlink(path)
    }
}
