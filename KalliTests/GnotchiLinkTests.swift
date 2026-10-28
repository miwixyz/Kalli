import XCTest

/// 0.11.0 Update-Meldung an Gnotchi (Gnotchi SECURE-DESIGN G23/G24): nur Kürzel und geprüfte Version raus,
/// nur „zeig dein Update-Fenster“ für Kalli rein.
@MainActor
final class GnotchiLinkTests: XCTestCase {

    func testPayloadOnlyPublicFields() throws {
        let p = try XCTUnwrap(GnotchiLink.payload(version: "0.11.0", ready: true))
        XCTAssertEqual(Set(p.keys), ["v", "app", "version", "ready"], "nichts außer Kürzel und Version")
        XCTAssertEqual(p["v"] as? Int, 1)
        XCTAssertEqual(p["app"] as? String, "kalli")
        XCTAssertEqual(p["version"] as? String, "0.11.0")
        XCTAssertEqual(p["ready"] as? Bool, true)
    }

    func testPayloadRejectsVersionGnotchiWouldReject() {
        for bad in ["1", "1.2.3.4", "1000.0", "0.11.0-beta", "0.11.0 (42)", ""] {
            XCTAssertNil(GnotchiLink.payload(version: bad, ready: true), bad)
        }
        XCTAssertNotNil(GnotchiLink.payload(version: "0.11", ready: false))
    }

    func testMessageOnChange() {
        XCTAssertEqual(GnotchiLink.message(old: nil, new: "0.11.0")?["ready"] as? Bool, true)
        XCTAssertEqual(GnotchiLink.message(old: "0.11.0", new: "0.12.0")?["version"] as? String, "0.12.0")
        let done = GnotchiLink.message(old: "0.11.0", new: nil)
        XCTAssertEqual(done?["ready"] as? Bool, false)
        XCTAssertEqual(done?["version"] as? String, "0.11.0", "erledigt mit der zuletzt gemeldeten Version")
        XCTAssertNil(GnotchiLink.message(old: "0.11.0", new: "0.11.0"), "keine Änderung, keine Meldung")
        XCTAssertNil(GnotchiLink.message(old: nil, new: nil))
    }

    func testShowRequestOnlyForKalli() {
        XCTAssertTrue(GnotchiLink.isShowRequest(["v": 1, "app": "kalli"]))
        XCTAssertFalse(GnotchiLink.isShowRequest(["v": 1, "app": "seam"]))
        XCTAssertFalse(GnotchiLink.isShowRequest(["v": true, "app": "kalli"]), "Bool statt Zahl")
        XCTAssertFalse(GnotchiLink.isShowRequest(["v": 2, "app": "kalli"]))
        XCTAssertFalse(GnotchiLink.isShowRequest(["app": "kalli"]))
        XCTAssertFalse(GnotchiLink.isShowRequest(nil))
    }

    func testGnotchiVersionAndSetting() {
        XCTAssertTrue(GnotchiLink.versionSupported("0.4.0"))
        XCTAssertTrue(GnotchiLink.versionSupported("1.0"))
        XCTAssertFalse(GnotchiLink.versionSupported("0.3.0"), "vor 0.4.0 kennt Gnotchi die Meldung nicht")
        XCTAssertFalse(GnotchiLink.versionSupported(nil))
        XCTAssertFalse(GnotchiLink.versionSupported("0.4.x"))
        XCTAssertTrue(GnotchiLink.settingAllows(nil), "fehlt = ab Werk an")
        XCTAssertFalse(GnotchiLink.settingAllows(false))
        XCTAssertTrue(GnotchiLink.settingAllows("nein"), "falscher Typ = ab Werk")
    }

    func testRequirementPinsGnotchiAndTeam() {
        XCTAssertTrue(GnotchiLink.requirement.contains(#"identifier "dev.mwlr.gnotchi""#))
        XCTAssertTrue(GnotchiLink.requirement.contains("LTKJ6Z2VYB"))
        XCTAssertTrue(GnotchiLink.requirement.contains("6.2.6"), "Developer ID, nicht Apple Development")
    }

    func testShowOnlyWithOwnUpdate() {
        var ready = false
        var shown = 0
        let sender = GnotchiUpdateSender(hasUpdate: { ready }, showUpdate: { shown += 1 })
        DistributedNotificationCenter.default().postNotificationName(
            GnotchiLink.showName, object: nil, userInfo: ["v": 1, "app": "kalli"], deliverImmediately: true)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        XCTAssertEqual(shown, 0, "ohne eigenes Update nichts zeigen")
        ready = true
        DistributedNotificationCenter.default().postNotificationName(
            GnotchiLink.showName, object: nil, userInfo: ["v": 1, "app": "seam"], deliverImmediately: true)
        DistributedNotificationCenter.default().postNotificationName(
            GnotchiLink.showName, object: nil, userInfo: ["v": 1, "app": "kalli"], deliverImmediately: true)
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        XCTAssertEqual(shown, 1, "nur die Bitte an Kalli, nur mit Update")
        withExtendedLifetime(sender) {}
    }
}
