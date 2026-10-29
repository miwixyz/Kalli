# Kalli – Sicherheitsentwurf

Bisher lagen Kallis Sicherheitsentscheidungen verteilt im Code und in `docs/AUTO-UPDATE-DESIGN.md`. Diese Datei
beginnt mit dem ersten Teil, der eine eigene Schnittstelle nach außen öffnet. Nummerierung „K“ für Kalli.

### K1 – Bild-Testkopie mit Befehlskanal: nur Debug, eigene Kennung, feste Befehle (neu, 2026-10-29, nach 0.12.0)

Übertragen von Gnotchis G45 (`~/Coding/Gnotchi/docs/SECURE-DESIGN.md`). Entwurf mit `rafter-secure-design`
(Ingestion + Threat-Modeling) **vor** dem Code; Entscheidungen von Michael (Aufgabe „Debug-Befehlskanal und
Fensterbilder für eigene Mac-Apps“, 28.10.).

- **Wozu:** Sichttests sollen Kallis Ansichten selbst prüfen können (hell/dunkel), statt die Optik Michael zu
  übergeben. Das Bild macht die App aus sich heraus per ScreenCaptureKit; das Claude-Terminal darf keine
  Bildschirmfotos (`screencapture` verboten).
- **Nie ausgeliefert:** Kanal, Bild-Kennung und Steuerkennung stehen nur in `#if DEBUG` (`Kalli/Debug/*`,
  `Kalli/Core/BildKopie.swift`). Nachweis am Release-Build per `strings` (`debug.sock`, `dev.mwlr.kalli.bild`,
  `dev.mwlr.kalli.ctl`, „Befehlskanal“ je 0×) und `otool -L` (ScreenCaptureKit nicht gelinkt); Gegenprobe am
  Debug-Build je ≥ 1×. Messwerte unten unter „Prüfung“.
- **Eigene Kennung `dev.mwlr.kalli.bild`:** Die Bildschirmaufnahme-Freigabe hängt an Kennung + Signatur-Anforderung.
  Mit `com.kalli.app` hätte auch das veröffentlichte Kalli die Freigabe. Der Kanal startet nur, wenn Debug-Build
  **und** diese Kennung zusammenkommen; `scripts/dev-signed.sh` (echte Kennung) hat ihn nicht.
- **Keine echten Daten, keine Wirkung nach außen:**
  - Kalli hat heute keinen eigenen Ordner unter `~/Library/Application Support` und keine eigenen Sockets – es gibt
    also keinen fest „Kalli“ heißenden Pfad, den die Kopie mitbenutzen würde. Einstellungen, „die eine Sache“ und
    Gruppenzustand liegen in `UserDefaults.standard` → mit eigener Kennung automatisch eigene Domäne. Der
    Kanal bekommt einen eigenen Ordner `~/Library/Application Support/Kalli Bild` (0700).
  - **Keine Berechtigungen:** leere Entitlements. Unter Hardened Runtime lehnt macOS Kalender- und
    Erinnerungs-Anfragen ohne Entitlement sofort ab (gemessen 2026-09-22, siehe `Kalli.entitlements`) – die Kopie
    sieht nie einen Termin. Keine Apple Events.
  - **Kein Updater:** Sparkle wird in der Kopie nicht gestartet (`startingUpdater: false`, keine Prüfung, kein Netz).
  - **Keine Verbindung zu Gnotchi:** weder `GnotchiEventSender` (Termine an `kalli.sock`) noch `GnotchiUpdateSender`
    (Update-Meldung über distnoted) laufen in der Kopie. Ihr leeres „nächster Termin“ hätte sonst Gnotchis echte
    Anzeige überschrieben.
  - **Kein Dienste-Menü:** `bild-test.sh` entfernt `NSServices` aus der Info.plist der Kopie, und sie meldet keinen
    Dienste-Anbieter an. Sonst stünde „Als eine Sache in Kalli“ doppelt im Dienste-Menü und könnte in der Kopie
    landen.
- **Wer darf steuern (Spoofing):** `debug.sock` über `DebugSocketServer` (schlanke Übertragung von Gnotchis
  `PeerSocketServer`): Ordner 0700 (echter Ordner, gehört dem Nutzer, kein Link), Socket 0600, eine alte
  Socket-Datei wird nur entfernt, wenn sie ein Socket des Nutzers ist. Jede Verbindung wird **vor dem ersten
  gelesenen Byte** über das Audit-Token (nicht die PID – kein Wettlauf mit wiederverwendeten Nummern) gegen
  Developer ID + Kennung `dev.mwlr.kalli.ctl` + Team LTKJ6Z2VYB geprüft. Nicht nur `anchor apple generic`:
  Apple-Development-Builds tragen `get-task-allow`. `kallictl` prüft umgekehrt die Kopie, bevor es sendet.
- **Feste Befehle (Ingestion):** `DebugCommand.parse` (Tests `KalliTests/DebugCommandTests.swift`), JSON aus
  `JSONSerialization` (kein Code-Pfad im Parser), Rahmen = 4 Byte Länge + JSON, höchstens 4 KB, Länge 0 oder zu groß
  → Verbindung zu. `v` Zahl 1 (kein Wahrheitswert). `status`; `snapshot` nur für `einstellungen`/`hilfe`;
  `appearance` light/dark/system. `id` 1–32 Zeichen A–Z/a–z/0–9, sie wird Dateiname (kein Pfad-Ausbruch).
  Alles andere: verworfen, keine Antwort, Verbindung zu. Höchstens 10 Befehle/s, der Rest fällt weg (DoS).
- **Welche Fenster (Information disclosure):** Kalli hat keine eigenen Fenster – Einstellungen und Hilfe stehen im
  Popover. Die Kopie öffnet für `snapshot` deshalb ein eigenes Fenster mit **denselben Ansichten**
  (`SettingsView` bzw. `HelpView`, Popover-Breite) und nimmt **nur dieses eigene Fenster** auf
  (`SCContentFilter(desktopIndependentWindow:)`, gesucht über die eigene Fensternummer). Nicht wählbar:
  Kalender/Agenda, „die eine Sache“, Vollbild-Hinweis – sie zeigen im echten Kalli echte Inhalte (Termine,
  Aufgaben). In der Kopie wären sie zwar leer (keine Berechtigung), die Liste bleibt trotzdem fest wie bei G45.
- **Ausgaben:** `Antworten/<id>.json` und `Bilder/<id>-<fenster>.png` im eigenen 0700-Ordner. `status` liefert nur
  Zahlen/Kennungen: Version, Kennung, Freigabe Bildschirmaufnahme, Darstellung, Kalender-/Erinnerungs-Status als
  Zahl, offene eigene Fenster mit Größe. Keine Titel, keine Inhalte, nichts davon ins Protokoll. `kallictl` löscht
  die gelesene Antwort; Bilder bleiben bis zum Aufräumen liegen.
- **Repudiation:** nicht relevant (ein Nutzer, eigene Testkopie); Protokoll nur „Befehl ausgeführt“ ohne Inhalt.
- **Elevation:** Die Kopie hat keine Rechte, die ein Befehl ausnutzen könnte; kein Shell-Aufruf, keine Pfade aus
  der Nachricht außer der geprüften `id`.
- **Ort:** `~/Applications/Kalli Bild.app` – unter `/tmp` finden die Systemeinstellungen eine App nicht über ihre
  Kennung (Gnotchi, gemessen 28.10.) und zeigen den Schalter nie. Gleiche Kennung + gleiche Signatur am selben Ort
  → die Freigabe bleibt über Neubauten erhalten. Das echte `/Applications/Kalli.app` wird nicht angefasst;
  beendet wird nur die alte Kopie, über ihre Kennung (`tell application id`), nie über den Prozessnamen – beide
  Programme heißen „Kalli“.
- **Annahmen (Negative space):** Wir vertrauen dem eigenen Nutzerkonto. Schlimmster Einzelfall: ein Prozess des
  gleichen Nutzers mit eigener Developer-ID-Signatur von Team LTKJ6Z2VYB und Kennung `dev.mwlr.kalli.ctl` – also
  nur Michael selbst.
- **Restrisiko (hingenommen):** Ein Prozess des gleichen Nutzers kann den Socket löschen (Kanal fällt aus) und die
  PNGs lesen; sie zeigen nur Einstellungen/Hilfe einer Kopie ohne Daten. Die Kopie steht während des Laufs als
  zweites Kalli-Symbol in der Menüleiste. Die Freigabe für „Kalli Bild“ bleibt in den Systemeinstellungen stehen;
  entfernen per `tccutil reset ScreenCapture dev.mwlr.kalli.bild`.
- **Gemessen 2026-10-29** (Kopie PID 18789 neben dem echten Kalli PID 1391, das vorher und nachher lief):
  - `kallictl status` → Antwort mit Kennung `dev.mwlr.kalli.bild`, Kalender-/Erinnerungs-Status 0 (nie gefragt),
    Bildschirmaufnahme `false`. `appearance dark` → `darstellung` light → dark; zurück mit `appearance system`.
  - Ad-hoc-signierte Kopie von `kallictl` (gleiche Kennung) → kein `ok` (Exit 4), Protokoll
    „Verbindung abgelehnt (OSStatus -67050)“.
  - `snapshot kalender`, `appearance rot` → keine Antwort (15 s), keine Antwortdatei, Protokoll „ungültiger Befehl“.
  - `snapshot einstellungen` ohne Freigabe → `{"ok":false,"fehler":"Bildschirmaufnahme nicht freigegeben …"}`, kein
    Absturz.
  - Kopie: einziger Socket `debug.sock` (0600, Ordner 0700), keine Netz-Sockets, keine Verbindung zu Gnotchis
    `kalli.sock`, kein `NSServices`, Entitlements leer.
  - Release-Build (`make build CONFIG=Release`): `strings` findet `debug.sock`, `dev.mwlr.kalli.bild`,
    `dev.mwlr.kalli.ctl`, „Befehlskanal“ je 0×, ScreenCaptureKit nicht gelinkt. Debug-Build (`Kalli.debug.dylib`):
    2× / 1× / 1× / 6×, ScreenCaptureKit gelinkt.
- **Prüfung:** `rafter-code-review` lokal (2026-10-29, CWE-Top-25-Durchgang + `rafter secrets .`): keine Funde.
  Dateinamen nur aus geprüfter `id` und fester Fensterliste, Schreiben `.atomic` (ersetzt einen untergeschobenen Link,
  folgt ihm nicht) in 0700-Ordnern; kein Shell-Aufruf in der App; Peer-Prüfung beidseitig vor dem ersten Byte;
  Puffer durch 4-KB-Rahmen begrenzt; `bild-test.sh` beendet nur die PID zum vollen Pfad der Kopie, ohne
  Fremdeingaben. **Kein `rafter run`** (Kontingent leer bis 26.11., Michael 28.10.).
- **Noch nicht gemessen:** ein echtes Fensterbild (braucht Michaels Freigabe) und die Drossel (10/s) im Lauf –
  sie ist aus Gnotchi übernommen, aber in Kalli nicht eigens ausgelöst.
