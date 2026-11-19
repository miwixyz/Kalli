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
  - **Keine Berechtigungen, kein Kalender- und Erinnerungszugriff** (berichtigt 2026-11-17): leere Entitlements.
    Unter Hardened Runtime lehnt macOS damit **nur Kalender**-Anfragen sofort ab (gemessen 2026-09-22, siehe
    `Kalli.entitlements`). Für **Erinnerungen gilt das nicht** – bis 17.11. stand hier fälschlich „Kalender- und
    Erinnerungs-Anfragen“. Gemessen am 17.11. auf dem Mac mini: Kopie mit leeren Entitlements (`codesign -d
    --entitlements -` → `[Dict]` leer, `flags=0x10000(runtime)`), `kallictl status` → `erinnerungszugriff: 3`,
    `kalenderzugriff: 0`; `snapshot einstellungen` zeigte echte Listennamen, ein frischer `EKEventStore` in der Kopie
    sah 27 Listen. Weg dorthin: Das Popover fragte beim Öffnen (`canPrompt`, weil Kalender auf „nie gefragt“ stand)
    beide Berechtigungen an; der Erinnerungs-Dialog erschien und wurde bestätigt. Wann, ist nicht mehr messbar (das
    Protokoll reicht nicht so weit zurück, die TCC-Datenbank ist ohne Festplattenvollzugriff nicht lesbar).
    Die Abschottung liegt deshalb in drei Schichten, keine davon ist das Entitlement:
    1. **Code:** `CalendarStore.authorization(for:)` ist die einzige Stelle, die den Berechtigungsstand liest, und
       liefert in der Kopie immer `.denied`. Daran hängen `canPrompt` (Popover fragt nicht), `loadIfAlreadyAuthorized`,
       `refreshAccess`, `reminderLookup` und `QuickReminder.save`. Zusätzlich direkt gesperrt: `requestEvents`/
       `requestReminders` (auch der Knopf in den Einstellungen fragt nicht), `loadSources` (keine Listennamen),
       `fetchEvents`/`fetchReminders` (keine Einträge), `setCompleted` (kein Schreiben).
    2. **Info.plist der Kopie:** `bild-test.sh` entfernt die vier `NS…UsageDescription`-Texte für Kalender und
       Erinnerungen – ohne sie kann macOS der Kopie keinen Zugriffsdialog zeigen.
    3. **Prüfung:** `kallictl selftest`, Schritt „Kein Datenzugriff“, meldet FAIL bei erteilter Freigabe (Rohwert 3
       oder 4), bei ausgeschalteter Sperre oder wenn ein frischer `EKEventStore` mehr als 0 Kalender/Listen zählt.
       Die Probe zählt nur, liest keine Titel und fragt nicht an.
    Eine früher erteilte Freigabe bleibt bei macOS stehen, bis sie entzogen wird: `tccutil reset Reminders
    dev.mwlr.kalli.bild` (einmalig je Mac, auf dem die Kopie je bestätigt wurde). `kallictl status` meldet bewusst
    weiter den Rohwert von macOS, nicht den gesperrten Wert. Keine Apple Events.
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
  → Verbindung zu. `v` Zahl 1 (kein Wahrheitswert). `status`; `snapshot` nur für `einstellungen`/`hilfe`/`aufgaben` (Aufgaben-Pop-up, seit 17.11.2026, ausschließlich mit festen Beispielaufgaben aus `TaskDigest.demoView`, nie mit Erinnerungen);
  `appearance` light/dark/system, `selftest` (seit 16.11.2026, ohne Parameter: Abschottung, Ressourcen, Siegel, Einstellungen in Wegwerf-Suite, Erinnerungs-Erkennung, beide Fenster, Beobachter-Rauchtest mit Wegwerf-Speicher ohne Berechtigung und ohne Mitteilungen). `id` 1–32 Zeichen A–Z/a–z/0–9, sie wird Dateiname (kein Pfad-Ausbruch).
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

### K2 – Schnelleingabe aus Gnotchi: Kalli schreibt, prüft selbst, löscht nur Frisches (neu, 2026-11-19, nach 0.15.3)

Kalli-Seite von Gnotchis G61 (`~/Coding/Gnotchi/docs/SECURE-DESIGN.md`, Spezifikation
`~/Coding/Gnotchi/specs/2026-11-19-gnotchi-schnelleingabe.md`, mit Michael per `/grill-me` geklärt).

- **Wozu:** Gnotchi soll Termine und Erinnerungen aus einer Eingabezeile anlegen, ohne selbst Zugriff auf Kalender
  oder Erinnerungen zu bekommen (für Erinnerungen gibt es keinen Nur-Schreiben-Zugriff). Kalli hat den Zugriff schon
  und schreibt stellvertretend.
- **Weg:** dieselbe Verbindung wie der nächste Termin (G26): `kalli.sock`, beide Seiten prüfen die andere **vor dem
  ersten Byte** über das Audit-Token gegen die Developer-ID-Anforderung (Team LTKJ6Z2VYB, `com.kalli.app` /
  `dev.mwlr.gnotchi`). Neu ist nur, dass Kalli nach Gnotchis `ok` weiterliest. Rahmen wie bisher: 4 Byte Länge +
  JSON, höchstens 4 KB; ein kaputter Rahmen schließt die Verbindung.
- **Nachrichten:** Gnotchi → Kalli `{"v":2,"create":{id,kind,title,start,end,allDay,urgent}}` und
  `{"v":2,"undo":{"id"}}`; Kalli → Gnotchi `{"v":2,"result":{id,ok,error?}}`. Ohne `onRequest` (alte Verdrahtung,
  Tests) verwirft Kalli Eingehendes wie bis 0.15.
- **Kalli vertraut Gnotchi nicht blind** (`GnotchiQuickEntry.parse`, rein und getestet): Version genau 2, `id` eine
  UUID, `kind` nur `event`/`reminder`, Titel nach Trimmen 1–200 Zeichen ohne Steuerzeichen, Beginn zwischen jetzt −1
  Tag und +5 Jahren, Termin mit `end > start` und höchstens 24 h, unbekannte oder falsch getypte Felder → Ablehnung.
  Höchstens 20 Anlagen je Minute (`QuickEntryRateLimiter`); dieselbe `id` zweimal → „schon angelegt“.
- **Schreiben:** Termin in `defaultCalendarForNewEvents`, Erinnerung über `QuickReminder.save` (wie das „+“) bzw. ohne
  Fälligkeit. Danach liest Kalli den Eintrag über seine Kennung nach; nur wenn er da ist, geht `ok` zurück, sonst ein
  Fehler (kein falscher Erfolg). Kein Ort, keine Notiz, keine Teilnehmer, kein eigener Alarm.
- **Löschen nur Frisches:** `QuickEntryUndoLedger` merkt sich `id → EventKit-Kennung` **nur im Arbeitsspeicher**,
  30 s lang und nur für Einträge, die über diesen Weg entstanden. `undo` nimmt den Eintrag einmal heraus; fremde,
  ältere oder schon zurückgenommene Kennungen → Fehler. Kalli löscht also nie etwas, das nicht gerade eben über die
  Schnelleingabe entstand. Ist der Eintrag beim Zurücknehmen schon weg, meldet Kalli das als Fehler, nicht als Erfolg.
  Nach dem Löschen wird nachgelesen, dass er weg ist.
- **Reihenfolge und Last:** Anfragen laufen streng nacheinander (ein `undo` nie vor seinem `create`), höchstens 32
  warten, mehr → Verbindung zu. Ein Verbindungszähler verhindert, dass eine späte Antwort in eine neue Verbindung geht.
  Das Neuladen der Anzeige läuft nach der Antwort, damit Gnotchi nicht in sein Zeitlimit (4 s) läuft und Michael
  doppelt speichert.
- **Protokoll:** nur Art, Ergebnis und Ablehnungsgrund (feste Texte), nie Titel oder Zeitpunkt.
- **STRIDE:**
  - *S:* Nur ein Developer-ID-signiertes Gnotchi kommt durch die Peer-Prüfung; andere Programme erreichen den
    Rückkanal nicht.
  - *T:* Kalli prüft jedes Feld selbst; geschrieben wird genau, was geprüft wurde.
  - *R:* Protokoll wie oben.
  - *I:* Kalli schickt außer `ok`/Fehlertext nichts zurück, keine Kalendernamen, keine Kennungen aus EventKit.
  - *D:* 20 Anlagen je Minute, 32 wartende Anfragen, 4-KB-Rahmen.
  - *E:* Ein kompromittiertes Gnotchi könnte bis zu 20 Einträge je Minute anlegen und nur seine eigenen frischen
    wieder löschen. Lesen, Ändern oder Löschen bestehender Einträge ist über diesen Weg nicht möglich.
- **Zugriffstexte angepasst:** `NSCalendars…UsageDescription` sagte „ausschließlich lesend“; jetzt: neue Termine nur
  über Gnotchis Schnelleingabe, Bestehendes wird nicht geändert. Ebenso Hilfe, README, RECHTLICHES, Website.
- **Prüfung (19.11.):** `/code-audit` (Default) mit zwei Funden, beide behoben: (1) `undo` meldete Erfolg, wenn der
  Eintrag nicht gefunden wurde; (2) das Neuladen vor der Antwort ließ Gnotchi in sein Zeitlimit laufen („antwortet
  nicht“ → Michael hätte doppelt gespeichert). Sichttest am echten System mit Gnotchi: ein dritter Fehler, `readAck`
  verwarf Bytes, die im selben Lesevorgang hinter Gnotchis `ok` kamen; jetzt gehen sie in den Eingangspuffer, Test
  mit echter Socket-Verbindung. gitleaks und Swift-Advisories sauber. Kein `rafter run` (Zweitmeinung erst vor dem
  Release).
