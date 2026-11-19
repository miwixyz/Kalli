import Darwin
import Security
import XCTest

// SYNTHETISCH – erfundene Einträge, keine echten Kalenderdaten.

/// Schnelleingabe aus Gnotchi (Gnotchi SECURE-DESIGN G61): Kalli liest Anfragen streng, drosselt, weist Doppel ab
/// und nimmt nur eigene, frische Einträge zurück.
@MainActor
final class GnotchiQuickEntryTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    private func create(kind: String = "event", title: Any = "Zahnarzt", start: Any = 1_800_003_600.0,
                        end: Any = 1_800_007_200.0, allDay: Any = false, urgent: Any = false,
                        extra: [String: Any] = [:], id: String? = nil) -> [String: Any] {
        var body: [String: Any] = ["id": id ?? self.id.uuidString, "kind": kind, "title": title, "start": start,
                                   "end": end, "allDay": allDay, "urgent": urgent]
        body.merge(extra) { $1 }
        return ["v": 2, "create": body]
    }

    private func parsed(_ obj: [String: Any]) -> Result<GnotchiQuickEntry.Request, GnotchiQuickEntry.Rejection> {
        GnotchiQuickEntry.parse(obj, now: now)
    }

    // MARK: Lesen – gültig

    func testValidTimedEvent() {
        guard case .success(.create(let c)) = parsed(create()) else { return XCTFail("gültiger Termin") }
        XCTAssertEqual(c.kind, .event)
        XCTAssertEqual(c.title, "Zahnarzt")
        XCTAssertEqual(c.start, Date(timeIntervalSince1970: 1_800_003_600))
        XCTAssertEqual(c.end, Date(timeIntervalSince1970: 1_800_007_200))
    }

    func testValidAllDayEventAndReminders() {
        XCTAssertNotNil(try? parsed(create(allDay: true, extra: ["end": NSNull()])).get(), "ganztägiger Termin")
        XCTAssertNotNil(try? parsed(create(kind: "reminder", end: NSNull())).get(), "Erinnerung mit Uhrzeit")
        XCTAssertNotNil(try? parsed(create(kind: "reminder", end: NSNull(), allDay: true)).get(), "nur Datum")
        XCTAssertNotNil(try? parsed(create(kind: "reminder", start: NSNull(), end: NSNull(), urgent: true)).get(),
                        "ohne Datum, dringend")
    }

    func testTitleIsTrimmed() {
        guard case .success(.create(let c)) = parsed(create(title: "  Zahnarzt  ")) else { return XCTFail("Titel") }
        XCTAssertEqual(c.title, "Zahnarzt")
    }

    func testUndo() {
        XCTAssertEqual(try? parsed(["v": 2, "undo": ["id": id.uuidString]]).get(), .undo(id))
    }

    // MARK: Lesen – abgelehnt

    func testRejectsWrongShape() {
        XCTAssertEqual(parsed(["v": 2]).failure, .malformed)
        XCTAssertEqual(parsed(create(extra: ["location": "x"])).failure, .malformed, "kein fremdes Feld")
        var both = create(); both["undo"] = ["id": id.uuidString]
        XCTAssertEqual(parsed(both).failure, .malformed, "nicht create und undo zugleich")
        XCTAssertEqual(parsed(create(kind: "todo")).failure, .malformed)
        XCTAssertEqual(parsed(create(id: "kein-uuid")).failure, .malformed)
        XCTAssertEqual(parsed(["v": 2, "undo": ["id": id.uuidString, "x": 1]]).failure, .malformed)
    }

    func testRejectsLooseTypes() {
        XCTAssertEqual(parsed(create(allDay: 0)).failure, .malformed, "Zahl ist kein Wahrheitswert")
        XCTAssertEqual(parsed(create(start: true)).failure, .malformed, "Wahrheitswert ist keine Zeit")
        XCTAssertEqual(parsed(create(start: "1800003600")).failure, .malformed, "Text ist keine Zeit")
        XCTAssertEqual(parsed(create(title: 42)).failure, .malformed)
        XCTAssertFalse(GnotchiQuickEntry.isVersion2(["v": true]))
        XCTAssertFalse(GnotchiQuickEntry.isVersion2(["v": 1]))
    }

    func testRejectsBadTitles() {
        XCTAssertEqual(parsed(create(title: "   ")).failure, .invalidTitle)
        XCTAssertEqual(parsed(create(title: String(repeating: "a", count: 201))).failure, .invalidTitle)
        XCTAssertEqual(parsed(create(title: "Zahn\narzt")).failure, .invalidTitle, "kein Zeilenumbruch")
        XCTAssertEqual(parsed(create(title: "Zahn\u{0007}arzt")).failure, .invalidTitle, "kein Steuerzeichen")
        XCTAssertNotNil(try? parsed(create(title: String(repeating: "Ä", count: 200))).get(), "200 geht")
    }

    func testRejectsBadTimes() {
        XCTAssertEqual(parsed(create(start: NSNull(), end: NSNull())).failure, .invalidTime, "Termin ohne Beginn")
        XCTAssertEqual(parsed(create(end: NSNull())).failure, .invalidTime, "Termin mit Uhrzeit ohne Ende")
        XCTAssertEqual(parsed(create(end: 1_800_003_600.0)).failure, .invalidTime, "Ende = Beginn")
        XCTAssertEqual(parsed(create(end: 1_800_003_600.0 + 24 * 3600 + 1)).failure, .invalidTime, "über 24 h")
        XCTAssertEqual(parsed(create(allDay: true)).failure, .invalidTime, "ganztägig mit Ende")
        XCTAssertEqual(parsed(create(kind: "reminder")).failure, .invalidTime, "Erinnerung mit Ende")
        XCTAssertEqual(parsed(create(kind: "reminder", start: NSNull(), end: NSNull(), allDay: true)).failure,
                       .invalidTime, "ganztägig ohne Datum")
        let past = 1_800_000_000.0 - 24 * 3600 - 1
        XCTAssertEqual(parsed(create(start: past, end: past + 3600)).failure, .invalidTime, "vor gestern")
        let far = 1_800_000_000.0 + GnotchiQuickEntry.latestOffset + 1
        XCTAssertEqual(parsed(create(start: far, end: far + 3600)).failure, .invalidTime, "über fünf Jahre")
        XCTAssertEqual(parsed(create(start: Double.infinity)).failure, .malformed)
    }

    func testReplyCarriesIdEvenWhenRejected() {
        let r = GnotchiQuickEntry.reply(id: GnotchiQuickEntry.requestID(create(title: " ")), rejection: .invalidTitle)
        let result = r["result"] as? [String: Any]
        XCTAssertEqual(r["v"] as? Int, 2)
        XCTAssertEqual(result?["id"] as? String, id.uuidString)
        XCTAssertEqual(result?["ok"] as? Bool, false)
        XCTAssertNotNil(result?["error"] as? String)
        XCTAssertTrue((GnotchiQuickEntry.reply(id: nil, error: nil)["result"] as? [String: Any])?["id"] is NSNull)
    }

    // MARK: Drossel und Rückgängig-Liste

    func testRateLimiterSlidingWindow() {
        var limiter = QuickEntryRateLimiter(limit: 2, window: 60)
        XCTAssertTrue(limiter.allow(now: now))
        XCTAssertTrue(limiter.allow(now: now.addingTimeInterval(1)))
        XCTAssertFalse(limiter.allow(now: now.addingTimeInterval(2)))
        XCTAssertTrue(limiter.allow(now: now.addingTimeInterval(60)), "erster fällt aus dem Fenster")
    }

    func testUndoLedgerOnceOnlyAndExpires() {
        var ledger = QuickEntryUndoLedger(lifetime: 30)
        ledger.record(id, identifier: "ek-1", kind: .event, now: now)
        XCTAssertEqual(ledger.takeForUndo(id, now: now.addingTimeInterval(1))?.identifier, "ek-1")
        XCTAssertNil(ledger.takeForUndo(id, now: now.addingTimeInterval(2)), "nur einmal")
        ledger.restore(id)
        XCTAssertNotNil(ledger.takeForUndo(id, now: now.addingTimeInterval(3)), "nach Fehlschlag wieder frei")
        XCTAssertTrue(ledger.contains(id, now: now.addingTimeInterval(29)), "bleibt gesperrt")
        XCTAssertFalse(ledger.contains(id, now: now.addingTimeInterval(30)), "abgelaufen")
        XCTAssertNil(ledger.takeForUndo(UUID(), now: now), "fremde Kennung")
    }

    // MARK: Ablauf

    private final class Fake {
        var created: [GnotchiQuickEntry.Create] = []
        var removed: [String] = []
        var createResult: Result<String, GnotchiQuickEntry.Failure> = .success("ek-1")
        var removeMessage: String?
        var clock: Date
        init(clock: Date) { self.clock = clock }
    }

    private func service(_ fake: Fake) -> GnotchiQuickEntryService {
        GnotchiQuickEntryService(
            create: { entry in fake.created.append(entry); return fake.createResult },
            remove: { identifier, _ in fake.removed.append(identifier); return fake.removeMessage },
            now: { fake.clock })
    }

    private func ok(_ reply: [String: Any]?) -> Bool? { (reply?["result"] as? [String: Any])?["ok"] as? Bool }
    private func error(_ reply: [String: Any]?) -> String? { (reply?["result"] as? [String: Any])?["error"] as? String }

    private let undo: (UUID) -> [String: Any] = { ["v": 2, "undo": ["id": $0.uuidString]] }

    func testServiceCreatesOnceThenUndoes() async {
        let fake = Fake(clock: now)
        let s = service(fake)
        let first = await s.handle(create())
        XCTAssertEqual(ok(first), true)
        XCTAssertEqual(fake.created.count, 1)
        let again = await s.handle(create())
        XCTAssertEqual(error(again), GnotchiQuickEntry.Rejection.duplicate.message, "kein Doppel")
        XCTAssertEqual(fake.created.count, 1)
        fake.clock = now.addingTimeInterval(1.5)
        let undone = await s.handle(undo(id))
        XCTAssertEqual(ok(undone), true)
        XCTAssertEqual(fake.removed, ["ek-1"])
        let twice = await s.handle(undo(id))
        XCTAssertEqual(error(twice), GnotchiQuickEntry.Rejection.unknownUndo.message, "nur einmal")
        XCTAssertEqual(fake.removed.count, 1)
    }

    func testServiceUndoOnlyForOwnFreshEntries() async {
        let fake = Fake(clock: now)
        let s = service(fake)
        let foreign = await s.handle(undo(UUID()))
        XCTAssertEqual(ok(foreign), false, "fremde Kennung")
        _ = await s.handle(create())
        fake.clock = now.addingTimeInterval(31)
        let late = await s.handle(undo(id))
        XCTAssertEqual(ok(late), false, "zu spät")
        XCTAssertTrue(fake.removed.isEmpty, "nichts gelöscht")
    }

    func testServiceRestoresUndoWhenRemoveFails() async {
        let fake = Fake(clock: now)
        let s = service(fake)
        _ = await s.handle(create())
        fake.removeMessage = "Rückgängig hat nicht geklappt."
        let failed = await s.handle(undo(id))
        XCTAssertEqual(error(failed), "Rückgängig hat nicht geklappt.")
        fake.removeMessage = nil
        let retry = await s.handle(undo(id))
        XCTAssertEqual(ok(retry), true, "zweiter Versuch geht")
    }

    func testServiceThrottlesAndReportsFailures() async {
        let fake = Fake(clock: now)
        let s = service(fake)
        for _ in 0..<GnotchiQuickEntry.maxCreatesPerMinute {
            _ = await s.handle(create(id: UUID().uuidString))
        }
        let throttled = await s.handle(create(id: UUID().uuidString))
        XCTAssertEqual(error(throttled), GnotchiQuickEntry.Rejection.tooMany.message)
        XCTAssertEqual(fake.created.count, GnotchiQuickEntry.maxCreatesPerMinute)

        let fake2 = Fake(clock: now)
        fake2.createResult = .failure(.init(message: "Kein Zugriff"))
        let failed = await service(fake2).handle(create())
        XCTAssertEqual(error(failed), "Kein Zugriff", "Fehler geht an Gnotchi")
    }

    func testServiceIgnoresOtherMessagesAndRejectsGarbage() async {
        let fake = Fake(clock: now)
        let s = service(fake)
        let silent = await s.handle(["v": 1, "ok": true])
        XCTAssertNil(silent, "v:1 still ignorieren")
        let none = await s.handle(nil)
        XCTAssertNil(none)
        let garbage = await s.handle(["v": 2, "delete": ["id": id.uuidString]])
        XCTAssertEqual(ok(garbage), false)
        XCTAssertTrue(fake.created.isEmpty)
    }

    // MARK: Hin und zurück über den echten Socket

    func testRoundTripOverVerifiedSocket() async throws {
        let request = try XCTUnwrap(GnotchiEvents.frame(create(start: Date().timeIntervalSince1970 + 3600,
                                                               end: Date().timeIntervalSince1970 + 7200)))
        let server = try ReplyServer(sendAfterAck: request)
        defer { server.stop() }
        let fake = Fake(clock: Date())
        let s = service(fake)
        let sender = GnotchiEventSender(current: { nil }, path: server.path, requirement: try selfRequirement(),
                                        onRequest: { obj in await s.handle(obj) })
        sender.sendCurrent()
        XCTAssertTrue(sender.isConnected)
        let replies = await server.replies(atLeast: 2, timeout: 3)   // erst Kallis Termin-Nachricht, dann die Antwort
        let answer = replies.first { $0["result"] != nil }
        XCTAssertEqual(ok(answer), true)
        XCTAssertEqual(fake.created.map(\.title), ["Zahnarzt"])
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

private extension Result {
    var failure: Failure? {
        if case .failure(let f) = self { return f }
        return nil
    }
}

/// Server auf eigenem Thread: `ok`, dann die vorgegebene Anfrage, danach jede empfangene Nachricht sammeln.
private final class ReplyServer: @unchecked Sendable {
    let path = "/tmp/kqe-\(UUID().uuidString.prefix(8)).sock"
    private let fd: Int32
    private let request: Data
    private let lock = NSLock()
    private var received: [[String: Any]] = []

    init(sendAfterAck request: Data) throws {
        self.request = request
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
        let c = accept(fd, nil, nil)
        guard c >= 0 else { return }
        for data in [GnotchiEvents.frame(["v": 1, "ok": true]), request].compactMap({ $0 }) {
            _ = data.withUnsafeBytes { write(c, $0.baseAddress, data.count) }
        }
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 1024)
        while true {
            let n = read(c, &chunk, chunk.count)
            guard n > 0 else { break }
            buffer.append(contentsOf: chunk[0..<n])
            while case .message(let obj) = GnotchiEvents.nextFrame(&buffer) {
                lock.lock(); received.append(obj ?? [:]); lock.unlock()
            }
        }
        close(c)
    }

    @MainActor
    func replies(atLeast count: Int, timeout: TimeInterval) async -> [[String: Any]] {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            let r = lock.withLock { received }
            if r.count >= count { return r }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return lock.withLock { received }
    }

    func stop() {
        close(fd)
        unlink(path)
    }
}
