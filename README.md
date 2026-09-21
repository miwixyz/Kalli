# Kalli

Menüleisten-Kalender für macOS. Bewusst klein.

Zeigt Datum, Monatsraster, Termine und Erinnerungen — und sonst nichts.

## Warum es das gibt

Es gibt gute Menüleisten-Kalender. [Calendr](https://github.com/pakerwreah/Calendr)
(MIT, sehr ausgereift) und [Dato](https://sindresorhus.com/dato) (~15 € einmalig)
sind beide besser gepflegt als dieses Projekt es je sein wird — wer ihre Funktionen
braucht, sollte sie nehmen.

Kalli existiert für den umgekehrten Fall: Beide werden mit jedem Release *voller*,
nie leerer. Natural-Language-Eingabe, Zeitzonen-Schieberegler, 50+ Videokonferenz-Dienste,
Datumsrechner, Weltzeituhren. Wer nur wissen will, welcher Tag heute ist und was
ansteht, bezahlt das mit Oberfläche.

## Funktionen

- **Menüleiste:** Datum in frei wählbarem Format, optional der nächste Termin
  (Titel auf feste Länge gekürzt, damit die Leistenbreite nicht springt)
- **Popover:** Monatsraster mit Kalenderwochen, Punkt an Tagen mit Einträgen,
  Tagesliste mit Terminen und Erinnerungen
- **Kalender und Erinnerungslisten einzeln ein- und ausblendbar**, nach Account gruppiert
- **Hell/Dunkel** folgt dem System
- **Liquid Glass** auf dem Popover (macOS 26+)
- **Tagesliste nach Art gruppiert:** Ganztägig, Termine, Aufgaben — je mit
  eigener Markerform, damit die Bedeutung nicht allein an der Kalenderfarbe hängt
- **Fortschritt laufender Termine** — Balken im Popover, Restzeit in der Leiste
- **Hinweis auf Kommendes** mit einstellbarer Vorlaufzeit
- **Start bei der Anmeldung**, abschaltbar

Ausdrücklich nicht enthalten: Termine anlegen oder ändern (Kalli liest nur),
Natural-Language-Eingabe, Zeitzonen, Videokonferenz-Erkennung, Datumsrechner.

## Bauen

```bash
make build     # xcodegen + xcodebuild
make run       # bauen und aus dem build-Ordner starten
make install   # nach /Applications legen und starten
```

**`make install` ist nicht optional, wenn du den Autostart willst.**
`SMAppService` verlangt eine App an einem festen Ort mit stabiler Signatur.
Aus `build/` heraus vergisst macOS die Registrierung beim nächsten Build —
der Schalter zeigt das dann ehrlich als „nicht verfügbar" an, statt Erfolg
zu behaupten.

Voraussetzungen: macOS 26+, Xcode 27+, `xcodegen` (`brew install xcodegen`).

## Berechtigungen

Beim ersten Öffnen des Popovers fragt macOS nach Zugriff auf Kalender und
Erinnerungen. Beides ist **lesend** — Kalli schreibt nie zurück.

Wird der Dialog abgelehnt, bleibt die Liste leer. Die App zeigt dann eine
Anleitung mit Direktlink in die Systemeinstellungen, statt still nichts zu tun.

> **Hinweis für Entwicklungs-Builds:** TCC (der Berechtigungsdienst) bindet die
> Zustimmung an die Code-Signatur. Ein unsignierter Build bekommt keinen Zugriff.
> `make run` signiert deshalb ad-hoc; nach einem Signatur-Wechsel fragt macOS erneut.

## Aufbau

```
Kalli/
  App/     KalliApp (MenuBarExtra + Settings), MenuBarLabel (Leistentext + Timer)
  Core/    CalendarStore (EventKit, nur lesend), Preferences, Models
  UI/      PopoverView, MonthGrid, SettingsView, GlassBackground
```

Kein RxSwift, keine externen Pakete. `@Observable` und SwiftUI reichen für diese Größe.

## Vier Entscheidungen, die nicht offensichtlich sind

1. **Wiederkehrende Termine werden nicht selbst aufgelöst.** `EKEventStore`
   expandiert sie inklusive Ausnahmen und verschobener Einzeltermine. Eigene
   Wiederholungslogik ist eine Fehlerquelle für Monate.
2. **Ganztägige Termine haben keine Zeitzone.** EventKit liefert sie in GMT.
   Mit lokaler Zeitzone verglichen rutschen sie auf den Vortag — deshalb wird
   bei ihnen nur das Kalenderdatum verglichen.
3. **Der Autostart-Schalter liest den Systemzustand, statt ihn zu spiegeln.**
   Ein `Bool` in den UserDefaults würde falsch, sobald jemand den Eintrag in den
   Systemeinstellungen abschaltet — dann stünde „an", während nichts startet.
   `SMAppService.mainApp.status` wird bei jedem Anzeigen frisch erfragt, und
   nach dem Umschalten wird der *tatsächliche* Zustand übernommen, nicht der
   gewünschte.
4. **Liquid Glass nur auf dem Popover.** Vollflächige Transluzenz mittelt das
   Hintergrundbild auf seine Durchschnittsfarbe; auf buntem Schreibtisch werden
   Fenster zu farbigem Nebel. Die Einstellungen liegen deshalb im
   Popover selbst, nicht in einem eigenen Fenster.

## Lizenz

MIT.
