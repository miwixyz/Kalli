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
- **Nächster Termin** — Uhrzeit und Titel, gekürzt auf eine feste Länge, damit
  die Breite der Leiste nicht bei jedem Terminwechsel springt.
  Ist der Termin nicht heute, steht der Tag davor („morgen 08:00 Praxis").
- **Restzeit des laufenden Termins** — verdrängt den nächsten Termin, solange
  etwas läuft. Was gerade passiert, ist dringender als was kommt.

Schaltest du Symbol *und* Datum ab, bliebe der Eintrag leer und Kalli wäre in
der Leiste nicht mehr auffindbar. Das Symbol bleibt in dem Fall sichtbar.

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
