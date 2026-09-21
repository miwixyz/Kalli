# Kalli — Hilfe

Kalli zeigt deinen Kalender im Menübalken. Nur lesen, nie schreiben.

## Menüleiste

Das **Kalenderblatt mit der Tageszahl** ist immer da. Daneben lassen sich
einblenden:

- **Datum als Text** — Format frei wählbar (`EEE d. MMM` → Mo 21. Sep)
- **Nächster Termin** — Uhrzeit und Titel, gekürzt auf eine feste Länge, damit
  die Breite der Leiste nicht bei jedem Terminwechsel springt.
  Ist der Termin nicht heute, steht der Tag davor („morgen 08:00 Praxis").
- **Restzeit des laufenden Termins** — verdrängt den nächsten Termin, solange
  etwas läuft. Was gerade passiert, ist dringender als was kommt.

Schaltest du Symbol *und* Datum ab, bliebe der Eintrag leer und Kalli wäre in
der Leiste nicht mehr auffindbar. Das Symbol bleibt in dem Fall sichtbar.

## Popover

- **Monatsraster** — heute ist gefüllt in der Akzentfarbe, der angeklickte Tag
  bekommt einen Ring. Ein Punkt unter der Zahl heißt: an diesem Tag steht etwas an.
- **Kalenderwochen** links, abschaltbar
- **Hinweis oben** — was gerade läuft oder bald beginnt, mit Fortschrittsbalken.
  Die Vorlaufzeit ist einstellbar (5 bis 240 Minuten).
- **Tagesliste** in drei Gruppen:
  - **Ganztägig** (Balken-Marker)
  - **Termine** mit Uhrzeit (Kreis)
  - **Aufgaben** aus der Erinnerungen-App (Kreisumriss, abgehakt = durchgestrichen)

Die Farbe kommt jeweils vom Kalender, die **Form** von der Art. So bleibt die
Bedeutung erkennbar, auch wenn zwei Kalender ähnlich eingefärbt sind.

## Einstellungen

Zahnrad unten links, drei Reiter:

| Reiter | Inhalt |
|---|---|
| **Kalender** | Jeder Kalender und jede Erinnerungsliste einzeln ein- und ausblendbar, nach Account gruppiert |
| **Menüleiste** | Symbol, Datum, Datumsformat, nächster Termin, Kürzungslänge |
| **Ansicht** | Kalenderwochen, erledigte Erinnerungen, Fortschritt, Hinweis auf Kommendes, Start bei der Anmeldung |

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
**Erinnerungen**. Beides wird ausschließlich **gelesen**.

Wurde der Zugriff abgelehnt, bleibt die Liste leer und Kalli zeigt einen
Hinweis mit Direktlink in die Systemeinstellungen.

## Was Kalli nicht kann — und nicht können soll

Termine anlegen oder ändern · Eingabe in natürlicher Sprache · Weltzeituhren ·
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
- **Ein Termin sieht falsch aus** → Kalli liest nur; die Quelle ist die
  Kalender- oder Erinnerungen-App.
