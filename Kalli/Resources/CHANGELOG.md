# Changelog

Alle nennenswerten Änderungen an Kalli.

## [0.4.4] — 2026-09-22

### Behoben

- **Der Knopf „Fehlende Berechtigung anfragen" tat sichtbar nichts.** Michael:
  „Abfrage ist da, es geschieht nach Klick aber nichts."

  Ursache, im Nachbarcode gefunden: Die Ansicht las `store.eventPermission`
  **direkt im `body`**. Das ist eine `nonisolated var`, die
  `EKEventStore.authorizationStatus` aufruft — und damit **kein Teil des
  Observation-Graphen**. SwiftUI hatte keinen Grund, nach der Anfrage neu zu
  zeichnen. Die Anfrage konnte also gelingen, und die Anzeige blieb gleich.

  `LoginItemToggle` macht es im gleichen Datei seit Tag eins richtig:
  `@State` + `.onAppear`-Neulesen. Genau das Muster hätte ich nehmen müssen —
  „frisch lesen" heißt **in beobachtbaren Zustand hinein**, nicht mitten im
  `body`. Jetzt: `@State` für beide Berechtigungen, frisch gelesen beim
  Erscheinen und nach jeder Anfrage.

- **Wirkungslosigkeit ist jetzt sichtbar.** `requestAccess()` gibt zurück, ob
  sich **überhaupt etwas geändert** hat (Status vorher/nachher verglichen).
  Wenn nicht, sagt die App: „macOS hat keinen Dialog gezeigt" — samt Grund
  (die Entscheidung fiel schon einmal) und dem Knopf, der dann allein hilft.
  Ein Knopf, der nichts sichtbar tut, sieht wie ein kaputter Knopf aus.

- **Messpunkt für die Anfrage.** Status vor und nach dem Aufruf plus die
  Rückgabewerte landen im Protokoll:
  `log show --last 10m --predicate 'subsystem == "com.kalli.app"'`.
  Ob macOS keinen Dialog zeigt, ob die Anfrage fehlschlägt oder ob nur die
  Anzeige nicht nachzieht, war von außen nicht unterscheidbar — und Raten hat
  an diesem Tag mehrfach nicht funktioniert.

## [0.4.3] — 2026-09-22

### Behoben

- **Die fehlende Berechtigung wurde nie mehr angefragt — und war nirgends zu
  sehen.** Michael: „Die Kalender-Berechtigung wird nicht mehr abgefragt und es
  gibt keine Möglichkeit in der App das zu überprüfen und neu anzustoßen."
  Beides stimmte, und die Ursache war der eigene Fix aus 0.1.1:

  `loadIfAlreadyAuthorized()` setzte `access = .partial(events: true,
  reminders: false)`, sobald **eine** der beiden Berechtigungen schon erteilt
  war. Die Anfrage hing aber an `access == .unknown` — und war damit
  ausgeschlossen. Angezeigt wurde der Teilfall auch nicht: Der Hinweis im
  Popover hing an `.denied`. Ein Zustand, der den Anfrage-Pfad blockiert und
  keine Anzeige hat.

  Drei Änderungen:
  - **Gefragt wird jetzt nach dem, was zählt:** Steht eine der beiden auf
    `notDetermined`? Nur dann kann ein Dialog etwas bewirken.
  - **Einstellungen → Kalender** zeigt oben für Kalender und Erinnerungen
    getrennt den Zustand — **bei jedem Öffnen frisch von macOS gelesen**, nicht
    gespiegelt (gleiche Haltung wie beim Autostart). Mit *Anfragen* wo das wirkt
    und *Systemeinstellungen* wo nur das hilft. Ein Knopf, der nichts tun kann,
    wird nicht angeboten.
  - **Orange Zeile im Popover**, wenn etwas fehlt — blockiert die Ansicht nicht,
    ist aber nicht zu übersehen, und führt direkt hin.

  Ersetzt wurde dabei auch „Keine Kalender gefunden — **fehlt die
  Berechtigung?**". Eine Frage statt einer Antwort, ohne Weg zur Behebung.

- **`writeOnly` gilt als nicht erteilt.** Den Status gibt es nur für Kalender;
  Kalli liest ausschließlich. „Erteilt" anzuzeigen, während die Liste leer
  bleibt, wäre eine Behauptung. Durch Mutationsprobe abgenommen: Setzt man ihn
  auf „erteilt", fällt genau der zugehörige Test.

### Neu

- **5 weitere Tests** (48 gesamt) für die Abbildung von EventKits
  Berechtigungsstatus, inklusive der Zusicherung, dass **jeder** Zustand eine
  Beschriftung hat — ein leeres Label wäre genau die stille Lücke, die den
  Befund ausgelöst hat.

## [0.4.2] — 2026-09-22

### Behoben

- **Der Update-Knopf war nicht zu verstehen.** In 0.4.0 stand in der Fußzeile
  allein ein Kreispfeil. Michaels Rückmeldung nach dem ersten echten Update:
  „Das Reload-Icon allein ist aber nicht zu verstehen." Zu Recht — ein
  Kreispfeil in einer **Kalender**-App liest sich wie „Termine neu laden".

  Jetzt: Beschriftung **„Updates“** mit einem Pfeil nach unten
  (`arrow.down.circle`). Das Zahnrad daneben darf symbolfrei bleiben, weil es
  überall dasselbe bedeutet — dieses hier nicht.

- **Die In-App-Hilfe hatte den Updates-Abschnitt nie bekommen.** Für 0.4.0 war
  er geschrieben, aber das Skript, das ihn einsetzen sollte, brach an einem
  Anker ab: Im Text steht „eine dritte, **davon** unabhängige Berechtigung",
  mein Anker ließ das „davon" weg. Frühere Dateien desselben Laufs waren
  geschrieben, `HILFE.md` nicht — und die Erfolgsmeldung, auf die ich mich
  berief, war nie erschienen. Ich hatte nur das Ende der Ausgabe gelesen.

  Nachgeholt: Abschnitt **Updates** (von Hand / automatisch, was übertragen
  wird, warum ein Update sicher ist) plus ein Hinweis bei den Berechtigungen,
  dass der Netzzugriff Kallis eigene Frage ist und keine macOS-Berechtigung.

  **Zwei Lehren, beide über diesen Fall hinaus:** Bei einem Skript, das mehrere
  Dateien anfasst, muss geprüft werden, dass **alle** Erfolgsmeldungen
  erschienen sind — nicht nur die letzte Zeile. Und Schreiben, Committen,
  Freigeben gehören **nicht** in eine `&&`-Kette: Scheitert ein früher Schritt,
  laufen die späteren auf einem falschen Zustand weiter. Genau so entstand der
  Commit `a890e7a`, dessen Nachricht „0.4.2" behauptete, während die Version
  noch auf 0.4.1 stand. Diese Version braucht deshalb zwei Commits.

### Belegt

- **Das Update ist einmal echt durchgespielt** (0.4.0 → 0.4.1): angeboten,
  installiert, bestätigt. Das war das letzte offene Abnahmekriterium aus
  `docs/AUTO-UPDATE-DESIGN.md` — bei einem Updater lässt sich aus dem Code
  nicht schließen, dass er wirkt.

## [0.4.1] — 2026-09-22

### Behoben

- **Das Release-Gate prüfte die falsche Signaturart.** Es rief
  `sign_update --verify appcast.xml` — das prüft eine **Feed**-Signatur, ein
  separates, optionales Sparkle-Merkmal, das `generate_appcast` gar nicht
  erzeugt. Der Lauf für 0.4.0 brach daran ab, obwohl der Appcast korrekt war.

  Richtig ist die Frage: **Passt die Signatur im Appcast zum Archiv, das
  ausgeliefert wird?** Beide Richtungen gemessen — passende Signatur `EXIT 0`,
  ein einziges verfälschtes Zeichen „failed to pass signing verification".

  Gut, dass das Gate überhaupt geprüft hat: Es prüfte das Falsche, aber es hat
  nicht stillschweigend ausgeliefert.

- **Appcast-Prüfung parst mit Python statt `grep`.** Auf dem Entwickler-Mac ist
  `grep` auf **ugrep** gemappt, dessen Regex-Verhalten abweicht — die
  Signatur-Extraktion lief damit still leer. Eine stille Fehlextraktion ist an
  dieser Stelle besonders teuer.

## [0.4.0] — 2026-09-22

### Neu

- **Automatische Updates über Sparkle** — möglich geworden, weil das Repo
  öffentlich ist. Vollständiger Sicherheitsentwurf **vor** der ersten Zeile
  Code: [`docs/AUTO-UPDATE-DESIGN.md`](docs/AUTO-UPDATE-DESIGN.md), mit
  Datenflussdiagramm, STRIDE je Vertrauensgrenze, Missbrauchsfällen,
  verworfenen Alternativen und getragenen Restrisiken.

  - **Ab Werk aus.** `SUEnableAutomaticChecks` ist bewusst **nicht** gesetzt;
    Sparkle fragt dadurch beim ersten Mal. Kalli hatte bis 0.3.1 keinen
    Netzzugriff — ihn ab Werk einzuschalten wäre eine Vollmacht, die niemand
    erteilt hat. Gleiche Haltung wie bei Kalenderzugriff und Mitteilungen.
  - **Von Hand** jederzeit über das Pfeil-Symbol unten im Popover.
  - **Zwei unabhängige Signaturen** werden geprüft, bevor etwas ersetzt wird:
    EdDSA gegen den eingebauten öffentlichen Schlüssel **und** Apples
    Developer ID. Ein Angreifer bräuchte beide Schlüssel; ein manipulierter
    Appcast allein liefert nichts aus.
  - **Der Appcast liegt im Repo**, nicht in einem Gist. Jede Änderung daran ist
    damit ein öffentlicher, datierter Commit — die billigste
    Manipulationserkennung, die zu haben ist.
  - **Sparkle exakt auf 2.10.0**, `Package.resolved` versioniert und auf die
    Commit-SHA gepinnt. Ein verschobener Tag würde auffallen. Eine direkte
    Abhängigkeit, **null** transitive.
  - **Die Werkzeuge kommen aus derselben festgelegten Version**, die in der App
    steckt — nicht aus einem handplatzierten Ordner. Und ohne `2>/dev/null`:
    Der Appcast wird nach dem Signieren **kryptografisch gegengelesen**
    (`sign_update --verify`), zusätzlich werden Version und Download-URL
    geprüft. Ein still unsignierter Appcast wäre entweder „niemand kann
    updaten" oder etwas Schlimmeres.

### Geändert — Datenschutz-Zusage, im selben Commit

- **„Kalli sendet nichts" ist ersetzt, nicht relativiert.** Mit dem Updater wäre
  der Satz falsch geworden: Kalli ruft `raw.githubusercontent.com` ab und
  übermittelt dabei — wie jeder HTTP-Aufruf — IP-Adresse und implizit die
  installierte Version. Kein Tracking, keine Kennung, aber Verkehr, wo vorher
  keiner war.

  Offengelegt in `RECHTLICHES.md` (eigener Abschnitt mit dem, was GitHub sieht),
  `HILFE.md`, README und README-Fußzeile. Das war ein Abnahmekriterium des
  Entwurfs: **ohne diese Änderung wird nicht ausgeliefert.**

- **Lizenzhinweis für Fremdcode mitgeliefert.** Sparkle steht unter MIT, und MIT
  verlangt, dass Urheberhinweis und Lizenztext der **Auslieferung** beigefügt
  werden. Gemessen: Das ausgelieferte `Sparkle.framework` enthält **keine**
  Lizenzdatei. Kalli führt sie jetzt selbst mit — `THIRD-PARTY-LICENSES.md`, im
  Repo **und im App-Bundle**, erreichbar unter Einstellungen → Hilfe →
  Fremdcode. Das Doku-Gate prüft ihr Vorhandensein.

  Dabei fiel auf, dass `RECHTLICHES.md` einen Abschnitt „Verwendete
  Fremdsoftware: **Keine.**" trug. Richtiggestellt statt einen zweiten daneben
  zu setzen.

## [0.3.1] — 2026-09-22

### Neu

- **43 automatisierte Tests** (`make test`, unter einer Sekunde). Sie prüfen
  ausschließlich reine Entscheidungslogik: welcher Termin in die Leiste kommt,
  welcher eine Mitteilung bekommt, wie Beschriftungen und Kennungen gebildet
  werden. Kein EventKit, keine Berechtigungen, **keine Systemuhr** — jede
  geprüfte Funktion bekommt `now` übergeben.

  Die Tests sind rückwirkend zu **echten Fehlern** geschrieben, nicht zu Zeilen:
  der Termin von gestern, der als „läuft gerade" galt · der Tagesblock, der acht
  Stunden alles Kommende verdeckte · die Serien-Kennung, die Mitteilungen
  gegenseitig ersetzte · „00:00" bei Erinnerungen ohne Uhrzeit · die überfällige
  Aufgabe, die der Vergangenheitsfilter nicht verstecken darf.

- **Mutationsprobe als Abnahme der Tests.** Die behobenen Fehler wurden
  absichtlich wieder eingebaut, um zu prüfen, ob die Tests sie fangen. Sechs von
  sieben Regeln wurden sofort gefangen — **eine nicht**: Der Test zur
  Tagesgrenze war grün, obwohl die Prüfung im Code fehlte. Sein Aufbau benutzte
  einen 21-Stunden-Termin bei `now` = 12:00, und damit schloss ihn schon die
  Dauergrenze aus; die Tagesgrenze wurde nie befragt. Mit `now` = 12:00 ist die
  Regel sogar mathematisch verdeckt — sie greift nur am frühen Morgen. Der Test
  arbeitet jetzt mit 06:00 und einem Termin über Nacht und schreibt seine
  eigenen Vorbedingungen mit fest.

### Geändert

- **`make release` läuft jetzt die Tests**, als Schritt 2 von 9, vor dem Bauen.
  Ein Release ohne Abnahme ist ein Release ohne Abnahme; die Tests brauchen
  unter einer Sekunde.
- **Auswahl- und Kandidatenlogik als reine Funktionen** (`CalendarStore.nextEvent`,
  `.runningEvent`, `.eventID`, `EventAlerts.candidates`). Vorher lasen sie
  `Date()` selbst und waren damit nicht prüfbar. Verhalten unverändert; die eine
  inhaltliche Änderung ist `isDateInToday(start)` → `isDate(start, inSameDayAs: now)`
  — in der Anwendung identisch, aber ohne Griff zur Systemuhr.

## [0.3.0] — 2026-09-22

Ergebnis eines vollständigen Code-Audits vor der geplanten Veröffentlichung.
Drei Funde, alle behoben, plus einer, der beim Nachprüfen des eigenen Fixes
auffiel.

### Behoben

- **🔴 Ein Monatswechsel im Popover löschte die geplanten Mitteilungen.** Die
  Planung leitete „welcher Termin existiert noch?" aus der Liste ab, die die
  Oberfläche anzeigt — und die enthält nur den geladenen Monat ±7 Tage. Ein
  Klick auf „nächster Monat" ließ die heutigen Termine daraus verschwinden,
  worauf sie als *gelöscht* galten und ihre Mitteilungen entfernt wurden. Das
  Feature schaltete sich still ab, ausgelöst durch eine harmlose Navigation.
  Der Mitteilungs-Horizont wird jetzt **eigens abgefragt** (24 Stunden ab
  jetzt), unabhängig vom angezeigten Monat. Nebeneffekt: Ein **verschobener**
  Termin wird dadurch korrekt neu geplant.
- **🟠 Die Datenschutz-Zusage stimmte nicht mehr.** Dort stand „Keine
  Termininhalte", während Systemmitteilungen seit 0.2.0 Titel und Uhrzeit an
  macOS weitergeben — mit Folgen für Mitteilungszentrale und Sperrbildschirm.
  Jetzt vollständig offengelegt in `RECHTLICHES.md`, `HILFE.md`, README und
  README-Fußzeile, samt Hinweis, wie man Titel auf dem Sperrbildschirm
  abschaltet.
- **🟡 Serientermine teilten sich eine Kennung.** `eventIdentifier` ist laut
  EventKit-Vertrag für **alle** Vorkommen einer Serie identisch. Folge: Bei
  einem Termin, der mehrmals innerhalb von 24 Stunden wiederkehrt, wurde nur
  **eine** Mitteilung geplant (jede ersetzte die vorige), und `ForEach` bekam
  doppelte IDs, wenn zwei Vorkommen auf denselben Tag fielen. Die Kennung
  enthält jetzt zusätzlich die Startzeit. Bei täglichen Serien fiel das nie
  auf — bei „alle 4 Stunden" sofort.
- **Überflüssige EventKit-Abfrage** (beim Nachprüfen des eigenen Fixes
  gefunden): Der 24-Stunden-Horizont wurde bei jeder Kalenderänderung geholt,
  auch wenn Mitteilungen ausgeschaltet waren — und danach verworfen. Jetzt
  wird erst geprüft, dann abgefragt.

### Geändert

- **`make release` gibt keinen fremden Projektnamen mehr vor.** Das
  notarytool-Profil wird in der Reihenfolge `kalli-notary`, `notary`,
  `tippi-notary` gesucht und das gefundene **gemeldet** — ein stiller Rückfall
  wäre eine Überraschung beim Debuggen. Eigenes Profil weiter über
  `NOTARY_PROFILE=…`.

## [0.2.3] — 2026-09-22

### Behoben

- **Die Installationsanleitung hätte die App zerstört.** README und
  `release.sh` sagten `unzip`. `unzip` zerstört die Bundle-Metadaten eines
  signierten `.app` — Gatekeeper meldet danach „a sealed resource is missing or
  invalid", und das sieht nach einem kaputten Release aus, obwohl das Artefakt
  einwandfrei ist. Jetzt `ditto -x -k`, mit Begründung an beiden Stellen.
  (Ein Doppelklick im Finder war immer sicher; das Archivierungsprogramm macht
  es richtig.)
- **Das Release-Gate prüfte eine Stufe zu früh.** Es fragte Gatekeeper zum
  Build **vor** dem Packen und meldete „akzeptiert" — während das
  heruntergeladene ZIP abgelehnt wurde. Jetzt wird das ausgelieferte ZIP
  ausgepackt und geprüft: Ticket angeheftet, Gatekeeper-Urteil. Geprüft wird,
  was ankommt, nicht was gebaut wurde.

## [0.2.2] — 2026-09-22

### Neu

- **`make release`** — signiertes, notarisiertes ZIP und GitHub-Release.
  Damit läuft Kalli auf einem zweiten Mac **ohne Xcode**: Release herunterladen,
  nach `/Applications` ziehen, fertig.

  Der eigentliche Gewinn ist ein anderer: **TCC bindet die
  Kalender-Berechtigung an die Code-Signatur.** `make install` signiert ad-hoc,
  also bei jedem Build anders — macOS fragt deshalb immer wieder neu. Mit einer
  stabilen Developer-ID-Signatur fragt es einmal, auf jedem Mac.

  Bewusst **kein Sparkle und kein Appcast** (Entscheidung vom 2026-09-21 gilt
  weiter): ein öffentlicher Appcast geht bei privatem Repo nicht. Ein
  Release-Asset geht trotzdem — `gh release download` läuft mit der eigenen
  Anmeldung. Bewusst **ZIP statt DMG**: Ein DMG lohnt sich, wenn ein
  Installationsfenster etwas erklären muss; hier zieht einer eine App nach
  `/Applications`.

  Das Skript prüft **vor** dem Bauen Zertifikat, Notar-Profil, sauberen Baum
  und CHANGELOG-Abschnitt — und **nach** dem Bauen, ob wirklich mit Developer
  ID signiert wurde, ob das Hardened Runtime aktiv ist, ob Apple angenommen
  hat, ob das Ticket angeheftet ist und ob Gatekeeper die App akzeptiert. Zum
  Schluss fragt es GitHub, ob das Asset dort liegt: Ein lokal erfolgreicher
  Ablauf sagt nichts darüber, was veröffentlicht ist.

  Übernommen aus Tippis Release-Pfad, nicht neu erfunden: `archive` +
  `exportArchive` statt `build`. Manuelles Signieren ohne Profil-Angabe bettet
  gar kein Provisioning-Profil ein — unsichtbar, solange die App keine
  Entitlements hat, und ein Startabbruch durch `amfid` (-413), sobald doch.

## [0.2.1] — 2026-09-22

### Behoben

- **Zwei Ankreuzfelder untereinander mit umgekehrter Logik.** „Erledigte
  Erinnerungen **anzeigen**" stand direkt über „Vergangene Termine
  **ausblenden**" — angekreuzt bedeutete einmal mehr und einmal weniger zu
  sehen. Beide fragen jetzt positiv: **„Vergangene Termine anzeigen"**.
  Apples HIG rät von negativ formulierten Ankreuzfeldern ab; „ausblenden" plus
  Häkchen ist eine doppelte Negation, die man bei jedem Blick neu übersetzt.

  **Die gespeicherte Einstellung bleibt unberührt.** Intern heißt der Schlüssel
  weiter `hidePastEvents`; die Oberfläche liest ihn nur umgekehrt. Ein
  Umbenennen hätte bei jedem bestehenden Nutzer die Einstellung still
  umgedeutet — wer „ausblenden" angehakt hatte, hätte plötzlich alles gesehen.
  Eine Umbenennung, die Verhalten ändert, ist keine Umbenennung.

## [0.2.0] — 2026-09-22

### Neu

- **Prominenter Hinweis vor dem nächsten Termin** — zwei Kanäle, **beide ab
  Werk aus** und einzeln schaltbar. Eine Unterbrechung erteilt man, man erbt
  sie nicht.
  - **Systemmitteilung** mit Titel, Uhrzeit und Dauer. Die Berechtigung wird
    erst beim Einschalten erfragt, nie beim Start. Verweigert macOS sie,
    springt der Schalter zurück und Kalli sagt es — ein Schalter, der „an"
    zeigt und nichts tut, wäre eine Behauptung.
  - **Pulsierender Punkt in der Leiste**, Wechsel zwischen `●` und `○`.
    Bewusst zwei Zeichen **gleicher Breite**: ein Wechsel zwischen Zeichen und
    Nichts ließe die Leiste im Sekundentakt springen. Der Sekundentakt läuft
    nur innerhalb der Vorlaufzeit und wird danach abgeräumt.
- **Vorlauf 5, 10 oder 30 Minuten** — gemeinsam für beide Kanäle. Zwei
  getrennte Zeiten für dieselbe Frage wären zwei Zahlen, die auseinanderlaufen.
- **Kein Doppel-Alarm:** Kalli meldet nur Termine, die im Kalender keinen
  eigenen Alarm tragen. Sonst klingelt es zweimal für denselben Termin — und
  dann glaubt man keinem von beiden.

### Behoben

- **Mitteilungen wären bei offenem Popover stillschweigend unterdrückt worden.**
  macOS zeigt sie nicht, wenn die App vordergründig ist — also genau dann, wenn
  man in den Kalender schaut. Ein `UNUserNotificationCenterDelegate` erzwingt
  die Anzeige.
- **Doku-Drift aus 0.1.1 nachgezogen.** Sowohl die In-App-Hilfe als auch der
  Erklärtext in den Einstellungen behaupteten noch, ein laufender Termin
  verdränge den nächsten und „laufende Termine erscheinen hier nie". Beides war
  seit 0.1.1 falsch.

## [0.1.3] — 2026-09-22

### Behoben

- **Bei überlappenden Terminen stand der falsche in der Leiste.** Laufen
  mehrere gleichzeitig, gewinnt jetzt der, der **zuerst endet**. Vorher nahm
  Kalli den mit dem frühesten Start — und damit bei „Praxis 08:00–16:00" acht
  Stunden lang die Praxis, obwohl um 10:00 ein Termin über 30 Minuten darin
  lag. Wer wissen will, wann er wieder frei ist, meint den nächsten
  Endzeitpunkt, nicht den ältesten Anfang.
- **Bei gleicher Startzeit gewinnt der kürzere Termin.** „P&O 10:00–10:30" ist
  konkreter als „Abfrage 10:00–12:00". Vorher entschied die Reihenfolge, in der
  EventKit die Termine zufällig lieferte.
- **Der Messpunkt fürs Abhaken war stumpf.** Die Bestätigung lief auf Stufe
  `info`, und die hält macOS nur im Speicher — im Protokoll stand danach
  nichts. Jetzt `notice`, also dauerhaft nachlesbar.

## [0.1.2] — 2026-09-22

### Neu

- **Countdown in der Leiste** — der nächste Termin steht jetzt mit „in 13 Min."
  dort. Nur für heute: „morgen 08:00 Praxis in 22:15 Std." wäre eine Zahl, die
  niemand liest — der Tagesname sagt es schon.

### Behoben

- **Abgehaktes wurde nicht nachgeprüft.** Ein `save()` ohne Fehler heißt nur,
  dass der Aufruf durchgelaufen ist — nicht, dass das Kennzeichen steht. Kalli
  liest das Häkchen jetzt frisch aus EventKit zurück und meldet ausdrücklich,
  wenn Apple Erinnerungen die Änderung nicht übernommen hat. Vorher blendete
  sich die Zeile nach drei Sekunden aus und sah nach Erfolg aus, egal was
  wirklich passiert war.
- **Die Fehlermeldung lag unter der Falz.** Sie stand innerhalb der
  Scrollfläche hinter der Terminliste und war bei voller Agenda nur nach
  Scrollen zu sehen. Eine Meldung, die man suchen muss, ist keine — sie hat
  jetzt einen festen Platz über der Fußzeile.
- **Messpunkt für das Abhaken**, lesbar von außen:
  `log show --last 15m --predicate 'subsystem == "com.kalli.app"' --info`

## [0.1.1] — 2026-09-22

Zwei Befunde aus dem ersten Tag im Alltag. Beide gemessen, nicht vermutet.

### Behoben

- **Die Leiste war nach jedem Start leer, bis man das Symbol anklickte.**
  `reload()` stieg aus, solange kein Monat geladen war — und geladen wurde
  ausschließlich vom Popover. Der Minuten-Timer rechnete also brav über eine
  leere Liste: Erfolg gemeldet, während die Vorbedingung verletzt war. Die App
  lädt jetzt beim Start selbst, sofern die Berechtigung schon erteilt ist. Der
  Vorsatz, beim Login **keinen** Berechtigungsdialog aufzuwerfen, bleibt
  unangetastet — es wird nur der Status gelesen, nie gefragt.
- **Ein laufender Termin verdrängte den nächsten vollständig.** Bei
  „Praxis 08:00–16:00" hieß das acht Stunden Fortschrittsbalken, während zwei
  Termine um 10:00 die Leiste nie erreichten. Jetzt gilt: **was kommt, schlägt
  was läuft** — sobald der nächste Termin in Vorlaufzeit ist, steht er in der
  Leiste. Der Fortschritt des laufenden Termins bleibt im Popover, wo Platz
  dafür ist.

## [0.1.0] — 2026-09-21

Erste Fassung, in einer Sitzung gebaut.

### Enthalten

- **App-Symbol** — Kalli als 3D-Maskottchen, Geschwister von Tippi: gleiche
  Bauform, gleiche Farbwelt, aber ein Kalenderblatt statt einer Sprechblase
- **App-Symbol in der Hilfe sichtbar** — Kalli hat kein Dock-Symbol und kein
  „Über"-Fenster; ohne diesen Platz wäre das Maskottchen nur im Finder zu sehen
- **Menüleisten-Symbol** — Kallis Kopf-Silhouette mit der heutigen Tageszahl.
  Gleiche Kopfform wie Tippis Leistensymbol, damit beide Apps nebeneinander als
  Familie lesbar sind; an die Stelle des Visiers tritt die Zahl. Template-Image
  (folgt Hell/Dunkel), abschaltbar
- **Hilfe, Änderungen und Rechtliches in der App** — als Dateien im Bundle,
  bei jedem Build frisch gespiegelt; die Versionsnummer kommt aus der Info.plist
- **Start bei der Anmeldung** über `SMAppService`, Systemzustand wird gelesen
  statt gespiegelt
- **Fortschritt laufender Termine** — Balken im Popover, Restzeit in der Leiste;
  nur für Termine, die heute begannen und unter 12 Stunden dauern
- **Hinweis auf Kommendes** mit einstellbarer Vorlaufzeit
- **Aufgaben direkt abhaken** — ein Klick auf den Kreis setzt das
  Erledigt-Kennzeichen in der Erinnerungen-App, ein weiterer nimmt es zurück.
  Der Marker ist zugleich der Schalter; ein separater Knopf wäre eine zweite
  Stelle für dieselbe Information. Fehler werden angezeigt statt geschluckt —
  ein Häkchen, das sichtbar gesetzt wird und nicht ankommt, ist schlimmer als
  eine Fehlermeldung.
  **Damit gilt „Kalli schreibt nie" nicht mehr.** Geschrieben wird ausschließlich
  dieses eine Kennzeichen; Info.plist, RECHTLICHES, HILFE und README sind
  entsprechend nachgezogen.
- **Vorlaufzeit für den nächsten Termin in der Leiste** — 15 Min., 30 Min.,
  1 Stunde oder 2 Stunden. Davor bleibt die Leiste schmal. Eigener Wert,
  getrennt vom Popover-Hinweis: Die Leiste ist immer sichtbar und muss knapp
  bleiben, das Popover sieht man nur auf Klick
- **Eigene Akzentfarbe** (`#3070F0`, aus der Tippi-Familie) statt der
  System-Akzentfarbe, als Verlauf mit weichem Schein. Heute ist jetzt ein
  gefüllter **Kreis**, der ausgewählte Tag ein Ring — Kreise wirken leichter
  als Kacheln und sind die Form, die Apple für „jetzt" verwendet
- **Eigener Fortschrittsbalken** mit runden Enden statt `ProgressView(.linear)`;
  der Systembalken bringt eigene Höhe, Einfassung und eine eckige Spur mit, die
  sich nicht anpassen lassen
- **Hinweisfläche** in Markenfarbe mit feiner Kontur statt grauem Kasten
- **Schriftgröße in fünf Stufen** — über `dynamicTypeSize` für alle Texte, plus
  ein Layoutfaktor für Rasterzellen und Fensterbreite. Beides muss zusammen
  skalieren; eine Stufe statt Punktwerte je Textstelle, weil die App durchgehend
  semantische Schriften nutzt. *Nachgebessert:* Das Monatsraster nutzte feste
  Punktgrößen (`.system(size:)`), die `dynamicTypeSize` grundsätzlich ignorieren —
  dort wirkt jetzt derselbe Faktor wie für die Zellen
- **Nachleuchten beim Abhaken** — die erledigte Aufgabe bleibt drei Sekunden
  sichtbar (durchgestrichen, abgedunkelt, mit Rückgängig-Knopf) und blendet
  dann aus. Vorher verschwand sie im selben Moment wie der Klick, womit ein
  Versehen von einer Absicht nicht zu unterscheiden war
- **Vergangene Termine ausblendbar** — nur für den heutigen Tag, ganztägige
  Termine und Aufgaben bleiben sichtbar. Ein Hinweis unter der Liste nennt die
  Zahl der verborgenen Einträge und zeigt sie auf Klick wieder
- **Tagesliste in drei Gruppen** — Ganztägig, Termine, Aufgaben, je mit eigener
  Markerform
- Menüleiste: Datum in frei wählbarem Format; optional der nächste Termin,
  auf eine feste Zeichenzahl gekürzt, damit die Leistenbreite nicht springt
- Popover mit Monatsraster (Kalenderwochen abschaltbar), Punktmarkierung an
  Tagen mit Einträgen, Sprung zu „Heute"
- Tagesliste mit Terminen **und Erinnerungen**; Termine zuerst, Erinnerungen
  darunter, weil sie oft keine Uhrzeit haben
- Kalender und Erinnerungslisten einzeln ein-/ausblendbar, nach Account gruppiert
- Hell/Dunkel folgt dem System; Liquid Glass auf dem Popover
- Klare Anleitung statt leerer Liste, wenn die Berechtigung fehlt

### Bewusst nicht enthalten
Termine anlegen/ändern, Aufgaben anlegen/umbenennen/löschen, Natural-Language-Eingabe, Weltzeituhren,
Zeitzonen-Schieberegler, Videokonferenz-Erkennung, Datumsrechner, Shortcuts.

### Behoben während der Entwicklung

- **Absturz beim ersten Erteilen der Berechtigung.** Das Mapping der
  Erinnerungen stand in einer `@MainActor`-Klasse und erbte deren Isolation,
  lief aber auf EventKits Queue. Swift 6 prüft das zur Laufzeit
  (`_dispatch_assert_queue_fail`). Jetzt explizit `nonisolated`.
- **App war in der Menüleiste unsichtbar** — ein reines Text-Label verschwindet
  spurlos, wenn der Text leer ist. Das Symbol wird jetzt immer gezeichnet.
- **Einstellungen waren unerreichbar** — `openSettings()` läuft in einer
  `LSUIElement`-App wirkungslos durch. Die Einstellungen liegen jetzt im
  Popover selbst.
- **Erinnerungen ohne Uhrzeit zeigten „00:00"** — ein Fälligkeitsdatum ohne
  Zeitanteil liefert Mitternacht; das ist keine Uhrzeit, sondern die
  Abwesenheit einer.
- **Ein Termin von gestern galt als „läuft gerade"** — `start <= now && end > now`
  trifft auch mehrtägige Termine.
- **Terminliste war auf eine Zeile gequetscht** — eine `ScrollView` hat keine
  eigene Höhe und bekommt im `VStack` sonst nur das Minimum.
- **Heute und ausgewählter Tag sahen gleich aus** — dieselbe Farbe in zwei
  Deckkraftstufen sind keine zwei Zustände. Jetzt Füllung gegen Ring.

### Technische Entscheidungen
- Kein RxSwift, keine externen Pakete — `@Observable`, SwiftUI, `MenuBarExtra`
- Swift 6 mit `SWIFT_STRICT_CONCURRENCY: complete`, Build warnungsfrei
- Kein `nonisolated(unsafe)` und kein `assumeIsolated`: EventKit-Objekte werden
  im Callback sofort in `Sendable`-Werte gemappt, statt die Isolationsgrenze
  mit einer Behauptung zu überqueren
- Wiederkehrende Termine werden von EventKit expandiert, nicht selbst gerechnet
- Ganztägige Termine werden nur nach Kalenderdatum verglichen (sie haben keine
  Zeitzone und rutschen sonst auf den Vortag)
- **Kein Sparkle.** Automatische Updates brauchen einen öffentlich erreichbaren
  Appcast; das Repo ist privat. `git pull && make install` ist der Update-Weg.
- **Doku als Bundle-Ressource statt als Swift-String**, plus ein Gate, das eine
  Installation blockiert, wenn die Doku dem Code hinterherhinkt
