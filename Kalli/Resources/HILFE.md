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
- **Nächster Termin** — Uhrzeit, Titel und Countdown („10:00 P&O in 13 Min."),
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
  endet** — nicht der, der zuerst begann. Wer wissen will, wann er wieder frei
  ist, meint den nächsten Endzeitpunkt. Die Leiste wandert damit von innen nach
  außen: erst der 30-Minuten-Termin, dann der zweistündige, dann der Tagesblock.

Schaltest du Symbol *und* Datum ab, bliebe der Eintrag leer und Kalli wäre in
der Leiste nicht mehr auffindbar. Das Symbol bleibt in dem Fall sichtbar.

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
  - **Termine** mit Uhrzeit (Kreis)
  - **Aufgaben** aus der Erinnerungen-App (Kreisumriss, abgehakt = durchgestrichen).
    **Ein Klick auf den Kreis hakt die Aufgabe ab** — die Änderung landet sofort in
    der Erinnerungen-App.

    Die Zeile bleibt danach **drei Sekunden lang sichtbar**: durchgestrichen,
    abgedunkelt und mit einem **Rückgängig**-Knopf. Erst dann blendet sie aus.
    Ohne dieses Nachleuchten verschwände sie im selben Moment wie der Klick —
    und ein Versehen wäre von einer Absicht nicht zu unterscheiden.

    Sind erledigte Erinnerungen eingeblendet (Einstellungen → Ansicht), bleibt
    die Zeile ohnehin stehen; ein weiterer Klick nimmt das Häkchen zurück.

**Vergangene Termine ausblenden** (Einstellungen → Ansicht) räumt die Liste im
Lauf des Tages auf. Der Filter gilt **nur für heute** — an anderen Tagen wäre
entweder alles vergangen oder nichts, und die Liste sähe leer statt aufgeräumt
aus. Ganztägige Termine und Aufgaben bleiben sichtbar: Eine überfällige Aufgabe
ist nicht erledigt, sondern das Gegenteil davon.

Unter der Liste steht dann, wie viele Einträge verborgen sind — ein Klick darauf
zeigt sie wieder. Eine versteckte Zeile ohne Hinweis sieht aus wie ein fehlender
Termin.

Die Farbe kommt jeweils vom Kalender, die **Form** von der Art. So bleibt die
Bedeutung erkennbar, auch wenn zwei Kalender ähnlich eingefärbt sind.

## Einstellungen

Zahnrad unten links, drei Reiter:

| Reiter | Inhalt |
|---|---|
| **Kalender** | Jeder Kalender und jede Erinnerungsliste einzeln ein- und ausblendbar, nach Account gruppiert |
| **Menüleiste** | Symbol, Datum, Datumsformat, nächster Termin, Kürzungslänge |
| **Ansicht** | Schriftgröße, Kalenderwochen, erledigte Erinnerungen, vergangene Termine, Fortschritt, Hinweis auf Kommendes, Start bei der Anmeldung |

## Start bei der Anmeldung

Der Schalter liegt unter **Ansicht**. Kalli fragt dabei nicht sich selbst,
sondern macOS — zeigt der Schalter „an", ist der Eintrag wirklich registriert.

Erscheint ein oranger Hinweis „macOS wartet auf deine Freigabe", musst du den
Eintrag einmal in den Systemeinstellungen bestätigen; der Knopf führt direkt
dorthin.

Steht dort „Autostart ist für diesen Build nicht verfügbar", liegt Kalli nicht
an einem festen Ort. `make install` legt die App nach `/Applications`.

## Berechtigungen

Beim ersten Öffnen fragt macOS nach Zugriff auf **Kalender** und
**Erinnerungen**.

Kalender werden ausschließlich **gelesen**. Bei Erinnerungen schreibt Kalli
genau eine Sache: das **Erledigt-Kennzeichen**, wenn du ein Häkchen setzt. Nichts
wird angelegt, umbenannt oder gelöscht.

Wurde der Zugriff abgelehnt, bleibt die Liste leer und Kalli zeigt einen
Hinweis mit Direktlink in die Systemeinstellungen.

**Mitteilungen** sind eine dritte, davon unabhängige Berechtigung. Sie wird
ausschließlich dann erfragt, wenn du „Systemmitteilung vor dem Termin"
einschaltest — nie beim Start.

## Was Kalli nicht kann — und nicht können soll

Termine anlegen oder ändern · Aufgaben anlegen, umbenennen oder löschen ·
Eingabe in natürlicher Sprache · Weltzeituhren ·
Zeitzonen-Umrechnung · Erkennung von Videokonferenz-Links · Datumsrechner ·
Benachrichtigungen.

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
