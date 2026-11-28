import XCTest

/// Zeiterfassung (0.21.0, aus MacStd übernommen): Buchen, Pausen, Wiederherstellen nach Neustart,
/// beschädigte Datei, Ton nur bei Nutzeraktion, Export, Menüleisten-Zustand.
@MainActor
final class ZeitErfassungTests: XCTestCase {

    private final class Uhr: @unchecked Sendable { var jetzt = Fixture.now }
    private final class Zaehler: @unchecked Sendable { var klaenge = 0; var an = true }

    private var ordner: URL!
    private var uhr: Uhr!
    private var ton: Zaehler!

    override func setUp() {
        ordner = FileManager.default.temporaryDirectory.appendingPathComponent("zeit-test-\(UUID().uuidString)")
        uhr = Uhr()
        ton = Zaehler()
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: ordner)
    }

    private var datei: URL { ordner.appendingPathComponent("zeit.json") }

    private func neu() -> ZeitErfassung {
        let u = uhr!, t = ton!
        return ZeitErfassung(store: ZeitStore(url: datei), now: { u.jetzt },
                             soundEnabled: { t.an }, playSound: { t.klaenge += 1 })
    }

    private func minuten(_ m: Double) { uhr.jetzt = Fixture.at(m) }

    // MARK: Buchen

    func testStartStoppBuchtEinenEintragMitNettozeit() {
        let z = neu()
        z.addProject(name: "Praxis")
        let id = z.projects[0].id
        z.toggle(projectID: id)
        XCTAssertEqual(z.zustand, .laeuft)
        minuten(30); z.pause()
        XCTAssertEqual(z.zustand, .pause)
        minuten(40); z.resume()
        minuten(70); z.stopByUser()
        XCTAssertEqual(z.zustand, .steht)
        XCTAssertEqual(z.entries.count, 1)
        XCTAssertEqual(z.entries[0].grossDuration, 70 * 60, accuracy: 0.5)
        XCTAssertEqual(z.entries[0].netDuration, 60 * 60, accuracy: 0.5)
    }

    func testProjektwechselBuchtAltesUndStartetNeuesMitEinemTon() {
        let z = neu()
        z.addProject(name: "A"); z.addProject(name: "B")
        z.toggle(projectID: z.projects[0].id)
        minuten(10)
        let klaengeVorher = ton.klaenge
        z.toggle(projectID: z.projects[1].id)
        XCTAssertEqual(z.entries.count, 1)
        XCTAssertEqual(z.activeProjectID, z.projects[1].id)
        XCTAssertEqual(ton.klaenge - klaengeVorher, 1)
    }

    func testStoppenInNullSekundenBuchtNichts() {
        let z = neu()
        z.addProject(name: "A")
        z.toggle(projectID: z.projects[0].id)
        z.stopByUser()
        XCTAssertTrue(z.entries.isEmpty)
    }

    func testBeendenBuchtLaufendeErfassungBisJetzt() {
        let z = neu()
        z.addProject(name: "A")
        z.toggle(projectID: z.projects[0].id)
        minuten(25)
        let klaengeVorher = ton.klaenge
        z.prepareForQuit()
        XCTAssertEqual(z.entries.count, 1)
        XCTAssertEqual(z.entries[0].netDuration, 25 * 60, accuracy: 0.5)
        XCTAssertEqual(ton.klaenge, klaengeVorher, "Beenden klingt nicht")
    }

    // MARK: Kommentar, kurze Timer, mehrere Timer je Projekt

    func testKommentarUeberstehtNeustartUndLandetImEintrag() {
        let z = neu()
        z.addProject(name: "A")
        z.toggle(projectID: z.projects[0].id)
        z.setNote("Telefonat Müller")
        let z2 = neu()
        XCTAssertEqual(z2.sessionNote, "Telefonat Müller")
        minuten(5); z2.stopByUser()
        XCTAssertEqual(z2.entries[0].note, "Telefonat Müller")
        XCTAssertEqual(z2.sessionNote, "", "nächster Timer startet ohne Kommentar")
    }

    func testMehrereTimerImSelbenProjektMitEigenenKommentaren() {
        let z = neu()
        z.addProject(name: "A")
        let id = z.projects[0].id
        z.toggle(projectID: id); z.setNote("erste"); minuten(10); z.stopByUser()
        z.toggle(projectID: id); z.setNote("zweite"); minuten(25); z.stopByUser()
        XCTAssertEqual(z.entries.map(\.note), ["erste", "zweite"])
        let tag = DateInterval(start: Fixture.at(-60), end: Fixture.at(200))
        XCTAssertEqual(z.totalsByProject(in: tag).count, 1)
        XCTAssertEqual(z.totalsByProject(in: tag)[0].total, 25 * 60, accuracy: 0.5)
    }

    func testKurzerTimerWirdGebuchtUndZeigtSekunden() {
        let z = neu()
        z.addProject(name: "A")
        z.toggle(projectID: z.projects[0].id)
        uhr.jetzt = Fixture.now.addingTimeInterval(20)
        z.stopByUser()
        XCTAssertEqual(z.entries.count, 1)
        XCTAssertEqual(ZeitFormat.anzeige(z.entries[0].netDuration), "20 s")
        XCTAssertEqual(ZeitFormat.anzeige(59.4), "59 s")
        XCTAssertEqual(ZeitFormat.anzeige(60), "0:01")
        XCTAssertEqual(ZeitFormat.anzeige(3725), "1:02")
        let tag = DateInterval(start: Fixture.at(-60), end: Fixture.at(200))
        XCTAssertEqual(z.totalsByProject(in: tag).count, 1, "auch ein 20-s-Eintrag erscheint in der Übersicht")
    }

    func testSetNoteOhneLaufendeErfassungTutNichts() {
        let z = neu()
        z.setNote("x")
        XCTAssertEqual(z.sessionNote, "")
    }

    // MARK: Neustart und Datei

    func testLaufendeErfassungUeberstehtNeustartInklusivePause() {
        let z = neu()
        z.addProject(name: "A")
        z.toggle(projectID: z.projects[0].id)
        minuten(20); z.pause()
        let z2 = neu()
        XCTAssertEqual(z2.zustand, .pause)
        XCTAssertEqual(z2.activeProjectID, z.projects[0].id)
        minuten(50)
        XCTAssertEqual(z2.elapsed(at: Fixture.at(50)), 20 * 60, accuracy: 0.5, "Pause zählt nicht")
    }

    func testWiederherstellenVerwirftSessionOhneProjektSichtbar() throws {
        let z = neu()
        z.addProject(name: "A")
        z.toggle(projectID: z.projects[0].id)
        // Datei so ändern, dass das Projekt fehlt
        var daten = try JSONDecoder.zeit.decode(ZeitDaten.self, from: Data(contentsOf: datei))
        daten.projects = []
        try JSONEncoder.zeit.encode(daten).write(to: datei)
        let z2 = neu()
        XCTAssertEqual(z2.zustand, .steht)
        XCTAssertNotNil(z2.errorMessage)
    }

    func testBeschaedigteDateiWirdZurSeiteGelegtNichtUeberschrieben() throws {
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        let kaputt = Data("{ das ist kein json".utf8)
        try kaputt.write(to: datei)
        let z = neu()
        XCTAssertNotNil(z.errorMessage, "Fehler sichtbar")
        let gesichert = try FileManager.default.contentsOfDirectory(atPath: ordner.path).filter { $0.hasPrefix("zeit-defekt-") }
        XCTAssertEqual(gesichert.count, 1)
        XCTAssertEqual(try Data(contentsOf: ordner.appendingPathComponent(gesichert[0])), kaputt, "Inhalt unverändert gesichert")
        z.addProject(name: "A")   // darf die gesicherte Datei nicht berühren
        XCTAssertEqual(try Data(contentsOf: ordner.appendingPathComponent(gesichert[0])), kaputt)
    }

    func testLiestDateiformatVonMacStdSchema3() throws {
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        let json = """
        {"projects":[{"id":"11111111-1111-1111-1111-111111111111","name":"Alt","colorHex":"5E9EFF"}],
         "entries":[{"id":"22222222-2222-2222-2222-222222222222","projectID":"11111111-1111-1111-1111-111111111111",
                     "start":"2026-11-02T08:00:00Z","end":"2026-11-02T10:00:00Z","note":"x","pauses":[]}],
         "schemaVersion":3}
        """
        try Data(json.utf8).write(to: datei)
        let z = neu()
        XCTAssertNil(z.errorMessage)
        XCTAssertEqual(z.projects.map(\.name), ["Alt"])
        XCTAssertEqual(z.entries[0].netDuration, 7200, accuracy: 0.5)
    }

    // MARK: Bearbeiten

    func testUpdateLehntPausenLaengerAlsEintragAbUndFuehrtUeberlappungenZusammen() {
        let z = neu()
        z.addProject(name: "A")
        z.toggle(projectID: z.projects[0].id)
        minuten(60); z.stopByUser()
        let e = z.entries[0]
        let zuLang = [ZeitPause(start: Fixture.at(-10), end: Fixture.at(100))]
        XCTAssertTrue(z.update(ZeitEintrag(id: e.id, projectID: e.projectID, start: e.start, end: e.end, note: "", pauses: zuLang)))
        XCTAssertEqual(z.entries[0].pauseDurationTotal, 3600, accuracy: 0.5, "auf den Eintrag beschnitten")
        XCTAssertEqual(z.entries[0].netDuration, 0, accuracy: 0.5)
        let ueberlappend = [ZeitPause(start: Fixture.at(10), end: Fixture.at(20)), ZeitPause(start: Fixture.at(15), end: Fixture.at(30))]
        XCTAssertTrue(z.update(ZeitEintrag(id: e.id, projectID: e.projectID, start: e.start, end: e.end, note: " n ", pauses: ueberlappend)))
        XCTAssertEqual(z.entries[0].pauses.count, 1)
        XCTAssertEqual(z.entries[0].pauseDurationTotal, 20 * 60, accuracy: 0.5)
        XCTAssertEqual(z.entries[0].note, "n")
    }

    func testUpdateVertauschtVonBisStattFalscheDauer() {
        let z = neu()
        z.addProject(name: "A")
        z.toggle(projectID: z.projects[0].id)
        minuten(60); z.stopByUser()
        let e = z.entries[0]
        XCTAssertTrue(z.update(ZeitEintrag(id: e.id, projectID: e.projectID, start: e.end, end: e.start, note: "", pauses: [])))
        XCTAssertEqual(z.entries[0].grossDuration, 3600, accuracy: 0.5)
    }

    func testProjektLoeschenWaehrendLaufTrenntSessionUndEntferntEintraege() {
        let z = neu()
        z.addProject(name: "A")
        let id = z.projects[0].id
        z.toggle(projectID: id)
        minuten(5)
        z.deleteProject(id: id)
        XCTAssertEqual(z.zustand, .steht)
        XCTAssertTrue(z.entries.isEmpty && z.projects.isEmpty)
        XCTAssertNil(neu().activeProjectID, "auch in der Datei")
    }

    func testLeereProjektnamenWerdenAbgelehnt() {
        let z = neu()
        XCTAssertFalse(z.addProject(name: "   "))
        XCTAssertTrue(z.projects.isEmpty)
    }

    // MARK: Ton

    func testTonNurBeiSchalterAnUndNurBeiNutzeraktion() {
        let z = neu()
        z.addProject(name: "A")
        ton.an = false
        z.toggle(projectID: z.projects[0].id)
        z.stopByUser()
        XCTAssertEqual(ton.klaenge, 0)
        XCTAssertEqual(z.soundRequests, 2, "Anforderung zählt auch bei Schalter aus")
        ton.an = true
        z.toggle(projectID: z.projects[0].id)
        XCTAssertEqual(ton.klaenge, 1)
        z.pause(); z.resume()
        XCTAssertEqual(ton.klaenge, 1, "Pause klingt nicht")
    }

    // MARK: Auswertung

    func testWochenUndMonatsgrenzen() {
        let cal = Fixture.calendar
        let woche = ZeitErfassung.interval(.woche, containing: Fixture.now, calendar: cal)!
        XCTAssertEqual(cal.component(.weekday, from: woche.start), 2, "Montag")
        XCTAssertEqual(woche.duration, 7 * 86400, accuracy: 3700)
        let monat = ZeitErfassung.interval(.monat, containing: Fixture.now, calendar: cal)!
        XCTAssertEqual(cal.component(.day, from: monat.start), 1)
        XCTAssertEqual(cal.component(.month, from: ZeitErfassung.shift(Fixture.now, .monat, by: 1, calendar: cal)), 10)
    }

    func testSummenJeProjektNurImZeitraum() {
        let z = neu()
        z.addProject(name: "A"); z.addProject(name: "B")
        z.toggle(projectID: z.projects[0].id); minuten(60)
        z.toggle(projectID: z.projects[1].id); minuten(90); z.stopByUser()
        let tag = DateInterval(start: Fixture.at(-60), end: Fixture.at(200))
        let summen = z.totalsByProject(in: tag)
        XCTAssertEqual(summen.map(\.project.name), ["A", "B"])
        XCTAssertEqual(summen[0].total, 3600, accuracy: 0.5)
        XCTAssertEqual(summen[1].total, 1800, accuracy: 0.5)
        XCTAssertTrue(z.totalsByProject(in: DateInterval(start: Fixture.at(500), end: Fixture.at(600))).isEmpty)
    }

    // MARK: Export

    func testCSVEntschaertFormelnUndSemikolon() {
        XCTAssertEqual(ZeitExport.field("=1+1"), "'=1+1")
        XCTAssertEqual(ZeitExport.field("a;b"), "\"a;b\"")
        XCTAssertEqual(ZeitExport.field("sie sagte \"hi\""), "\"sie sagte \"\"hi\"\"\"")
        XCTAssertEqual(ZeitExport.field("normal"), "normal")
    }

    func testCSVKopfUndZeile() {
        let p = ZeitProjekt(name: "=Praxis")
        let e = ZeitEintrag(projectID: p.id, start: Fixture.at(0), end: Fixture.at(60), note: "n")
        let text = ZeitExport.text(format: .csv, entries: [e], projects: [p], titel: "x")
        XCTAssertTrue(text.hasPrefix("\u{FEFF}entry_id;project;"))
        let zeilen = text.split(separator: "\n")
        XCTAssertEqual(zeilen.count, 2)
        XCTAssertTrue(zeilen[1].contains("'=Praxis"))
        XCTAssertTrue(zeilen[1].contains(";3600;3600;0;"))
    }

    func testMarkdownEnthaeltNettoUndPausen() {
        let p = ZeitProjekt(name: "A")
        let pause = ZeitPause(start: Fixture.at(30), end: Fixture.at(60))
        let e = ZeitEintrag(projectID: p.id, start: Fixture.at(0), end: Fixture.at(120), pauses: [pause])
        let text = ZeitExport.text(format: .markdown, entries: [e], projects: [p], titel: "KW 1")
        XCTAssertTrue(text.contains("# Arbeitszeiten KW 1"))
        XCTAssertTrue(text.contains("**Netto:** 1h 30m"))
        XCTAssertTrue(text.contains("**Pausen:**"))
    }

    // MARK: Menüleiste

    func testMenueleistenGesichtUndLaufzeit() {
        XCTAssertEqual(MenuBarLabel.face(zeit: .steht, day: 28), .day(28))
        XCTAssertEqual(MenuBarLabel.face(zeit: nil, day: 5), .day(5))
        XCTAssertEqual(MenuBarLabel.face(zeit: .laeuft, day: 28), .running)
        XCTAssertEqual(MenuBarLabel.face(zeit: .pause, day: 28), .paused)
        XCTAssertEqual(MenuBarLabel.laufzeit(0), "0:00")
        XCTAssertEqual(MenuBarLabel.laufzeit(65 * 60 + 59), "1:05")
        XCTAssertEqual(MenuBarLabel.laufzeit(10 * 3600), "10:00")
    }

    func testStandardPfadIstProKennungGetrennt() {
        // Im Testlauf ist die Kennung nicht die echte: die echten Zeiten bleiben unberührt.
        XCTAssertFalse(ZeitStore.standardURL().path.hasSuffix("Application Support/Kalli/zeit.json"))
    }
}

private extension JSONDecoder {
    static var zeit: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
}
private extension JSONEncoder {
    static var zeit: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }
}
