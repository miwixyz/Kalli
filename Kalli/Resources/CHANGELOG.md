# Changelog

Alle nennenswerten Änderungen an Kalli.

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
