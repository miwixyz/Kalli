# Kalli — Hilfe

Kalli zeigt deinen Kalender im Menübalken. Termine werden nur gelesen; Aufgaben lassen sich direkt abhaken.

## Menüleiste

**Kallis Symbol** — die Kopf-Silhouette mit der heutigen Tageszahl darin — ist
ab Werk sichtbar und unter Einstellungen → Menüleiste abschaltbar.

Die Form ist bewusst die gleiche wie bei Tippi: runder Kopf, zwei Ohren. So sind
die beiden Apps nebeneinander in der Leiste als Familie erkennbar. An die Stelle
von Tippis Visier tritt bei Kalli die Tageszahl — das Symbol ist damit zugleich
Marke und Information. Dass die Ohren dabei auch wie Kalenderringe wirken, ist
ein willkommener Zufall. Daneben lassen sich
einblenden:

- **Datum als Text** — Format frei wählbar (`EEE d. MMM` → Mo 21. Sep)
- **Termin in der Leiste** — Uhrzeit, Titel und Countdown („10:00 P&O in 13 Min."),
  gekürzt auf eine feste Länge, damit die Breite der Leiste nicht bei jedem
  Terminwechsel springt.
  Ist der Termin nicht heute, steht der Tag davor („morgen 08:00 Praxis") — dann
  ohne Countdown, weil der Tagesname die Angabe schon trägt.

  **Er erscheint erst kurz vorher** — wählbar 15 Min., 30 Min., 1 Stunde oder
  2 Stunden (Einstellungen → Menüleiste). Davor bleibt die Leiste schmal. Ein
  Termin, der erst in fünf Stunden beginnt, ist in einer stets sichtbaren Leiste
  kein Hinweis, sondern Belegung.

  Die Vorlaufzeit ist bewusst **getrennt** von der des Popover-Hinweises: Das
  Popover sieht man nur, wenn man es öffnet — dort darf früher gewarnt werden.
- **Restzeit des laufenden Termins** — erscheint, solange **kein** Termin in
  Vorlaufzeit ansteht. Was kommt, schlägt was läuft: Bei „Praxis 08:00–16:00"
  würde die Praxis sonst acht Stunden lang alles verdecken, was dazwischen
  liegt.

  Laufen mehrere Termine gleichzeitig, steht der in der Leiste, der **zuerst
  endet** — nicht der, der zuerst begann.

  Auch **über Mitternacht**: Ein Nachtdienst 22–06 zeigt um 03:00 seine
  Restzeit. Ausgenommen sind nur Termine über 12 Stunden — dort sagt eine
  Restzeit nichts.

  **Ganz ohne Termin in der Leiste:** „Termin in der Leiste anzeigen"
  abschalten. Dann erscheint weder ein kommender noch ein laufender — nur
  Symbol und Datum. Der Fortschrittsbalken **im Popover** bleibt davon
  unberührt; der hängt an „Fortschritt laufender Termine". Wer wissen will, wann er wieder frei
  ist, meint den nächsten Endzeitpunkt. Die Leiste wandert damit von innen nach
  außen: erst der 30-Minuten-Termin, dann der zweistündige, dann der Tagesblock.

Die Leiste zeigt immer, was **jetzt** ansteht — unabhängig davon, welchen Monat
das Popover gerade zeigt oder ob es seit Tagen nicht geöffnet wurde.

Schaltest du Symbol *und* Datum ab, bliebe der Eintrag leer und Kalli wäre in
der Leiste nicht mehr auffindbar. Das Symbol bleibt in dem Fall sichtbar —
ebenso, wenn der Text aus einem anderen Grund leer wäre (z. B. ein leeres
Datumsformat).

### Prominenter Hinweis vor dem Termin

Zwei Kanäle, **beide ab Werk aus** und einzeln schaltbar (Einstellungen →
Menüleiste). Eine Unterbrechung erteilt man, man erbt sie nicht.

- **Systemmitteilung** — erscheint oben rechts mit Titel, Uhrzeit und Dauer,
  auch im Vollbild und auch dann, wenn du gerade nicht in die Leiste schaust.
  Die Berechtigung wird **erst beim Einschalten** erfragt. Verweigert macOS sie,
  springt der Schalter zurück und Kalli sagt es — ein Schalter, der „an" zeigt
  und nichts tut, wäre eine Behauptung.
- **Pulsierender Punkt in der Leiste** — wechselt im Sekundentakt zwischen `●`
  und `○`. Bewusst zwei Zeichen gleicher Breite: ein Wechsel zwischen Zeichen
  und Nichts ließe die Leiste im Sekundentakt springen. Der Takt läuft nur
  innerhalb der Vorlaufzeit, nicht dauerhaft.

Der **Vorlauf** gilt für beide Kanäle gemeinsam: 5, 10 oder 30 Minuten. Zwei
getrennte Zeiten für dieselbe Frage („wann will ich Bescheid?") wären zwei
Zahlen, die auseinanderlaufen.

**Kalli meldet nur Termine ohne eigenen Alarm.** Trägt der Termin im Kalender
schon eine Erinnerung, meldet Apple Kalender selbst — Kalli hält dann still.
Zwei Klingeln für denselben Termin sind kein doppelter Hinweis, sondern einer,
dem man nicht mehr glaubt.

> **Was die Mitteilung enthält:** Titel und Uhrzeit des Termins. macOS speichert
> sie bis zur Auslieferung, danach steht sie in der Mitteilungszentrale, und je
> nach deinen Einstellungen erscheint der Titel **auf dem Sperrbildschirm**.
> Neben „Link öffnen“ im Vollbild-Hinweis ist das der einzige Fall, in dem ein
> Termininhalt Kalli verlässt. Nichts geht an einen Server. Wer keine Titel auf dem Sperrbildschirm will: macOS-
> Einstellungen → Mitteilungen → Kalli → *Vorschau anzeigen: Wenn entsperrt*.
> Details in **Rechtliches**.

Kalli plant die Mitteilungen bei jeder Kalenderänderung, nach dem Aufwachen,
beim Tageswechsel und stündlich neu. Wurde die Erlaubnis später in den
Systemeinstellungen entzogen, plant Kalli nichts und zeigt unter Einstellungen →
Menüleiste einen orangen Hinweis.

Eine Mitteilung kann ausbleiben, wenn der Mac aus ist, schläft oder „Nicht
stören" aktiv ist. Für Unverzichtbares bleibt der Alarm im Kalender selbst der
verlässlichere Weg.

### Vollbild-Hinweis vor dem Termin

Der dritte Kanal, für alle, die in der Arbeit versinken und Mitteilungen
übersehen. **Ab Werk aus**, einzuschalten unter Einstellungen → Menüleiste →
Vollbild-Hinweis.

- Kurz vor Beginn legt sich über **alle Bildschirme** eine Glasfläche über die
  untere Hälfte, darüber ein Verlauf. Deine Arbeit bleibt oben sichtbar.
- Du siehst Titel, Uhrzeit und einen Countdown („Beginnt in 1 Min.“).
- **Schließen** mit Esc, Return oder dem Knopf „Schließen“.
- **Eigener Vorlauf:** zum Beginn, 1, 2 oder 5 Minuten. Getrennt vom Vorlauf der
  Mitteilung, denn die warnt vor, der Vollbild-Hinweis holt dich im letzten
  Moment aus der Arbeit.
- Gilt für **alle Termine mit Uhrzeit**, auch mit eigenem Kalender-Alarm. Das
  ist ein anderer Kanal als eine Mitteilung, und gerade wichtige Termine haben
  meist einen Alarm. Nicht für ganztägige Termine und **nicht für abgelehnte
  Einladungen**.
- Beginnen mehrere Termine gleichzeitig, stehen sie in **einem** Hinweis.
- Schläft der Mac zum Zeitpunkt, holt Kalli den Hinweis nach dem Aufwachen nach,
  aber nur bis 5 Minuten nach Beginn.

**„Link öffnen“:** Steht im Termin ein Web-Link (URL-Feld, Ort oder Notizen),
zeigt der Hinweis einen Knopf mit der Zieladresse, z. B. „Link öffnen · zoom.us“.
Geöffnet wird nur auf Klick und nur `http`/`https`. Einladungen können von
Fremden stammen, und andere Adressarten könnten Programme starten. Kalli erkennt
keine einzelnen Videokonferenz-Dienste, es nimmt den ersten Web-Link.

> **Bildschirm teilen:** Der Hinweis liegt über allem, auch über einer geteilten
> Präsentation. Wer oft präsentiert, schaltet ihn vorher aus.

Das **App-Symbol** — Kalli als Maskottchen — steht unten in diesem Reiter. Es
taucht sonst nirgends auf: Kalli hat kein Dock-Symbol und kein „Über"-Fenster.

## Popover

- **Monatsraster** — heute ist ein gefüllter Kreis in Kallis Blau, der
  angeklickte Tag ein Ring. Ein Punkt unter der Zahl heißt: an diesem Tag steht etwas an.
- **Schriftgröße** in fünf Stufen (Einstellungen → Ansicht). Sie skaliert
  Schrift, Rasterzellen und Fensterbreite **gemeinsam** — sonst wüchse der Text
  und das Raster bliebe stehen.
- **Kalenderwochen** links, abschaltbar
- **Hinweis oben** — was gerade läuft oder bald beginnt, mit Fortschrittsbalken.
  Die Vorlaufzeit ist einstellbar (5 bis 240 Minuten).
- **Tagesliste** in drei Gruppen:
  - **Ganztägig** (Balken-Marker)
  - **Termine** mit Uhrzeit (Kreis). Ein Termin über Mitternacht steht an
    **jedem** Tag, den er berührt; endet er genau um 00:00, nicht mehr am
    Folgetag.
  - **Aufgaben** aus der Erinnerungen-App (Kreisumriss, abgehakt = durchgestrichen).
    **Ein Klick auf den Kreis hakt die Aufgabe ab** — die Änderung landet sofort in
    der Erinnerungen-App.

    Die Zeile bleibt danach **drei Sekunden lang sichtbar**: durchgestrichen,
    abgedunkelt und mit einem **Rückgängig**-Knopf. Erst dann blendet sie aus.
    Ohne dieses Nachleuchten verschwände sie im selben Moment wie der Klick —
    und ein Versehen wäre von einer Absicht nicht zu unterscheiden.

    Sind erledigte Erinnerungen eingeblendet (Einstellungen → Ansicht), bleibt
    die Zeile ohnehin stehen; ein weiterer Klick nimmt das Häkchen zurück.

    **Wiederkehrende Aufgaben** haben kein Rückgängig: Das Abhaken rückt dort
    womöglich die Fälligkeit auf das nächste Mal, ein Zurücknehmen träfe dann
    das falsche. Versehentlich abgehakt → in der Erinnerungen-App korrigieren.

**Vergangene Termine anzeigen** (Einstellungen → Ansicht) ist ab Werk an.
Abgeschaltet räumt sich die Liste im Lauf des Tages auf. Der Filter gilt **nur
für heute** — an anderen Tagen wäre
entweder alles vergangen oder nichts, und die Liste sähe leer statt aufgeräumt
aus. Ganztägige Termine und Aufgaben bleiben sichtbar: Eine überfällige Aufgabe
ist nicht erledigt, sondern das Gegenteil davon.

Unter der Liste steht dann, wie viele Einträge verborgen sind — ein Klick darauf
zeigt sie wieder. Eine versteckte Zeile ohne Hinweis sieht aus wie ein fehlender
Termin.

Die Farbe kommt jeweils vom Kalender, die **Form** von der Art. So bleibt die
Bedeutung erkennbar, auch wenn zwei Kalender ähnlich eingefärbt sind.

## Hell und Dunkel

Unten links neben dem Zahnrad sitzt ein runder Knopf. Jeder Klick schaltet
weiter: **System → Hell → Dunkel**. Das Symbol zeigt den aktuellen Stand
(Halbkreis, Sonne, Mond). Die Wahl gilt für ganz Kalli, also Kalender-Fenster,
Einstellungen und Vollbild-Hinweis. Dieselbe Wahl steht unter Einstellungen →
Ansicht → Darstellung.

## Einstellungen

Zahnrad unten links, drei Reiter. Jeder Bereich ist eine eigene Karte mit
farbigem Symbol, wie in den Systemeinstellungen:

| Reiter | Inhalt |
|---|---|
| **Kalender** | Berechtigungen · jeder Kalender und jede Erinnerungsliste einzeln ein- und ausblendbar, nach Account gruppiert |
| **Menüleiste** | Anzeige in der Leiste (Symbol, Datum, Format) · Termin in der Leiste · Hinweis vor dem Termin (Mitteilung, Puls) · Vollbild-Hinweis |
| **Ansicht** | Darstellung (Hell/Dunkel, Schriftgröße, Kalenderwochen) · Tagesliste · Laufend und kommend · System (Start bei der Anmeldung) |

## Start bei der Anmeldung

Der Schalter liegt unter **Ansicht**. Kalli fragt dabei nicht sich selbst,
sondern macOS — zeigt der Schalter „an", ist der Eintrag wirklich registriert.

Erscheint ein oranger Hinweis „macOS wartet auf deine Freigabe", musst du den
Eintrag einmal in den Systemeinstellungen bestätigen; der Knopf führt direkt
dorthin.

Steht dort „Autostart ist für diesen Build nicht verfügbar", liegt Kalli nicht
an einem festen Ort. `make install` legt die App nach `/Applications`.

## Updates

Kalli kann sich selbst aktualisieren. **Ab Werk fragt es nicht von allein** —
beim ersten Mal fragt es dich, ob es selbständig nachsehen darf.

- **Von Hand:** der Knopf **„Updates“** unten im Popover. Kalli sagt auch, wenn
  es **kein** Update gibt — ein Knopf, der nichts sichtbar tut, sieht wie ein
  kaputter Knopf aus.
- **Automatisch:** nur wenn du es erlaubt hast. Die Entscheidung lässt sich
  jederzeit ändern.

Sagst du nein, gibt es **keinen** Netzwerkzugriff, außer du drückst den Knopf.

**Was dabei übertragen wird:** Kalli ruft eine kleine Textdatei bei GitHub ab.
GitHub sieht dabei — wie bei jedem Aufruf einer Webadresse — deine IP-Adresse
und die installierte Version. Nichts darüber hinaus, keine Kalenderdaten.
Vollständig in **Rechtliches**.

**Warum ein Update sicher ist:** Jedes trägt zwei Signaturen, die Kalli prüft,
**bevor** es etwas ersetzt: die Signatur des Archivs und Apples
Developer-ID-Signatur. Die Archiv-Signatur ist in den Versionen nach 0.4.9
Pflicht — ohne sie wird ein Update nicht einmal entpackt. Die App-Signatur muss
unversehrt sein, darf aber bei einem Zertifikatswechsel neu sein. Bis 0.4.9
genügte eine der beiden; genauer in **Rechtliches**.

**Wenn die automatische Suche etwas findet,** öffnet Kalli **kein** Fenster —
macOS würde es hinter deine anderen Apps legen, wo man es nicht sieht. Stattdessen
kommt eine Mitteilung **„Kalli … ist da“**, und der Knopf unten heißt **„Update …“**.
Ein Klick auf eins von beiden öffnet das Update-Fenster, und zwar vorn.

Eine Mitteilung über ein Update kann ausbleiben, wenn der Mac aus ist oder
schläft. Der Knopf funktioniert immer.

## Berechtigungen

Beim ersten Öffnen fragt macOS nach Zugriff auf **Kalender** und
**Erinnerungen**.

Kalender werden ausschließlich **gelesen**. Bei Erinnerungen schreibt Kalli
genau eine Sache: das **Erledigt-Kennzeichen**, wenn du ein Häkchen setzt. Nichts
wird angelegt, umbenannt oder gelöscht.

Wurde der Zugriff abgelehnt, bleibt die Liste leer und Kalli zeigt einen
Hinweis mit Direktlink in die Systemeinstellungen. Erteilst du ihn dort später,
lädt Kalli beim nächsten Öffnen des Popovers — ohne Neustart.

**Stand prüfen und neu anstoßen:** Einstellungen → **Kalender**, ganz oben.
Dort steht für Kalender und Erinnerungen getrennt, ob die Berechtigung erteilt,
noch nicht gefragt, abgelehnt oder durch eine Geräteverwaltung gesperrt ist —
bei jedem Öffnen frisch von macOS gelesen, nicht gespiegelt.

- **„noch nicht gefragt"** → Knopf *Fehlende Berechtigung anfragen*
- **„abgelehnt"** → Knopf *Systemeinstellungen*. macOS zeigt den Dialog nur
  einmal; danach hilft ausschließlich dieser Weg.

Fehlt eine der beiden, erscheint außerdem oben im Popover eine orange Zeile
„Eine Berechtigung fehlt — hier prüfen", die direkt dorthin führt. Bis 0.4.2
war dieser Teilfall unsichtbar: Kalender erteilt, Erinnerungen nicht — die
Ansicht funktionierte, und nichts sagte, dass die Hälfte fehlt.

**Mitteilungen** sind eine dritte, davon unabhängige Berechtigung. Sie wird
ausschließlich dann erfragt, wenn du „Systemmitteilung vor dem Termin"
einschaltest — nie beim Start.

**Der Netzzugriff für Updates** ist keine macOS-Berechtigung, sondern Kallis
eigene Frage beim ersten Mal — siehe **Updates** oben. Bis dahin und bei einem
Nein findet kein Netzzugriff statt.

## Was Kalli nicht kann — und nicht können soll

Termine anlegen oder ändern · Aufgaben anlegen, umbenennen oder löschen ·
Eingabe in natürlicher Sprache · Weltzeituhren ·
Zeitzonen-Umrechnung · Erkennung einzelner Videokonferenz-Dienste (Kalli
nimmt nur den ersten Web-Link, siehe Vollbild-Hinweis) · Datumsrechner.

Das ist kein Rückstand, sondern der Zweck. Wer diese Dinge braucht, ist mit
[Calendr](https://github.com/pakerwreah/Calendr) (kostenlos, MIT) oder
[Dato](https://sindresorhus.com/dato) (einmalig ca. 15 €) besser bedient —
beide sind ausgereifter und werden gepflegt.

## Wenn etwas nicht stimmt

- **Kalli ist nicht in der Leiste** → Menüleiste voll? Symbol in den
  Einstellungen einschalten.
- **Liste bleibt leer** → Berechtigung prüfen, oder alle Kalender sind unter
  „Kalender" abgewählt.
- **Termin fehlt** → Gehört er zu einem abgewählten Kalender?
- **Ein Termin sieht falsch aus** → Termine werden nur gelesen; die Quelle ist
  die Kalender-App. Dort korrigieren, Kalli zieht automatisch nach.
- **Ein Häkchen kommt nicht an** → Kalli meldet den Fehler unter der Liste.
  Bleibt er bestehen, fehlt vermutlich die Schreibberechtigung für Erinnerungen
  (Systemeinstellungen → Datenschutz & Sicherheit → Erinnerungen).
