# Changelog

Alle nennenswerten Änderungen an MacCal.

## [0.1.0] — 2026-09-21

Erste Fassung, in einer Sitzung gebaut.

### Enthalten
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
Termine anlegen/ändern (MacCal liest nur), Natural-Language-Eingabe, Weltzeituhren,
Zeitzonen-Schieberegler, Videokonferenz-Erkennung, Datumsrechner, Shortcuts.

### Technische Entscheidungen
- Kein RxSwift, keine externen Pakete — `@Observable`, SwiftUI, `MenuBarExtra`
- Swift 6 mit `SWIFT_STRICT_CONCURRENCY: complete`, Build warnungsfrei
- Kein `nonisolated(unsafe)` und kein `assumeIsolated`: EventKit-Objekte werden
  im Callback sofort in `Sendable`-Werte gemappt, statt die Isolationsgrenze
  mit einer Behauptung zu überqueren
- Wiederkehrende Termine werden von EventKit expandiert, nicht selbst gerechnet
- Ganztägige Termine werden nur nach Kalenderdatum verglichen (sie haben keine
  Zeitzone und rutschen sonst auf den Vortag)
