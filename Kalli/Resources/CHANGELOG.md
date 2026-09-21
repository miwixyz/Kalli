# Changelog

Alle nennenswerten Änderungen an Kalli.

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
