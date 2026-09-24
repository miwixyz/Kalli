# Kalli

<img src="assets/Kalli-App_Icon.png" width="128" align="right" alt="Kalli">

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

- **Menüleiste:** Datum in frei wählbarem Format, optional ein Termin mit
  Countdown („10:00 P&O in 13 Min.", Titel auf feste Länge gekürzt, damit die
  Leistenbreite nicht springt). Ein Schalter, drei Zustände sind damit
  erreichbar: nächster Termin · laufender Termin, wenn nichts ansteht · **gar
  keiner**
- **Popover:** Monatsraster mit Kalenderwochen, Punkt an Tagen mit Einträgen,
  Tagesliste mit Terminen und Erinnerungen
- **Kalender und Erinnerungslisten einzeln ein- und ausblendbar**, nach Account gruppiert
- **Hell/Dunkel** folgt dem System
- **Liquid Glass** auf dem Popover (macOS 26+)
- **Tagesliste nach Art gruppiert:** Ganztägig, Termine, Aufgaben — je mit
  eigener Markerform, damit die Bedeutung nicht allein an der Kalenderfarbe hängt
- **Fortschritt laufender Termine** — Balken im Popover, Restzeit in der Leiste.
  In der Leiste hat der **nächste** Termin Vorrang, sobald er in Vorlaufzeit ist —
  ein Tagesblock würde sonst stundenlang alles verdecken, was dazwischen liegt.
  Laufen mehrere gleichzeitig, steht der dort, der **zuerst endet**
- **Hinweis auf Kommendes** mit einstellbarer Vorlaufzeit
- **Prominenter Hinweis vor dem Termin** — Systemmitteilung und/oder pulsierender
  Punkt in der Leiste, beide **ab Werk aus** und einzeln schaltbar, Vorlauf 5/10/30 Min.
  Kalli meldet nur Termine **ohne eigenen Kalender-Alarm** — sonst klingelte es zweimal.
  Die Mitteilung enthält Titel und Uhrzeit; was das für Mitteilungszentrale und
  Sperrbildschirm bedeutet, steht in `Kalli/Resources/RECHTLICHES.md`
- **Start bei der Anmeldung**, abschaltbar

**Aufgaben lassen sich direkt abhaken** — ein Klick auf den Kreis setzt das Erledigt-Kennzeichen
in der Erinnerungen-App. Kalli **liest das Kennzeichen danach zurück** und meldet, wenn es nicht
angekommen ist: Ein `save()` ohne Fehler heißt nur, dass der Aufruf durchlief.

Ausdrücklich nicht enthalten: Termine anlegen oder ändern, Aufgaben anlegen oder löschen,
Natural-Language-Eingabe, Zeitzonen, Videokonferenz-Erkennung, Datumsrechner.

## Bauen

```bash
make build     # xcodegen + xcodebuild
make test      # 43 Tests, unter einer Sekunde
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
Erinnerungen. Kalender werden **nur gelesen**. Bei Erinnerungen schreibt Kalli
ausschließlich das **Erledigt-Kennzeichen**, und nur auf Klick — nichts wird
angelegt, umbenannt oder gelöscht.

Wird der Dialog abgelehnt, bleibt die Liste leer. Die App zeigt dann eine
Anleitung mit Direktlink in die Systemeinstellungen, statt still nichts zu tun.

**Mitteilungen** sind eine dritte, unabhängige Berechtigung. Sie wird
ausschließlich beim Einschalten von „Systemmitteilung vor dem Termin" erfragt,
nie beim Start. Verweigert macOS sie, springt der Schalter zurück und die App
sagt es — ein Schalter, der „an" zeigt und nichts tut, wäre eine Behauptung.

Kalli gibt dabei **Titel und Uhrzeit** des Termins an macOS weiter — der einzige
Fall, in dem ein Termininhalt die App verlässt. Nichts davon geht an einen
Server. Vollständige Offenlegung inklusive Sperrbildschirm:
`Kalli/Resources/RECHTLICHES.md`.

> **Hinweis für Entwicklungs-Builds:** TCC (der Berechtigungsdienst) bindet die
> Zustimmung an die Code-Signatur. Ein unsignierter Build bekommt keinen Zugriff.
> `make run` signiert deshalb ad-hoc; nach einem Signatur-Wechsel fragt macOS erneut.

## Aufbau

```
Kalli/
  App/     KalliApp (MenuBarExtra + Settings), MenuBarLabel (Leistentext + Timer)
  Core/    CalendarStore (EventKit; schreibend nur das Erledigt-Kennzeichen), Preferences, Models,
           EventAlerts (Systemmitteilungen; plant idempotent, nur für Termine ohne eigenen Alarm)
  UI/      PopoverView, MonthGrid, SettingsView, GlassBackground
KalliTests/ Reine Entscheidungslogik — ohne EventKit, ohne Uhr
```

Eine direkte Abhängigkeit (**Sparkle**, für Updates), null transitive. Sonst
`@Observable` und SwiftUI — das reicht für diese Größe. Sparkle ist exakt auf
2.10.0 festgelegt, `Package.resolved` ist versioniert und pinnt die Commit-SHA;
ein verschobener Tag würde damit auffallen.

## Tests

```bash
make test
```

43 Tests, `KalliTests/`. Sie prüfen **ausschließlich reine Entscheidungslogik** —
welcher Termin in die Leiste kommt, welcher eine Mitteilung bekommt, wie
Beschriftungen und Kennungen gebildet werden. Kein EventKit, keine
Berechtigungen, keine Systemuhr: Jede geprüfte Funktion bekommt `now`
übergeben. Ein Test, der die Uhr befragt, schlägt irgendwann nachts fehl und
wird dann ignoriert statt gelesen.

Die Tests sind rückwirkend zu echten Fehlern geschrieben, nicht zu Zeilen. Jeder
prüft eine Regel, die einmal falsch war — mit dem Befund im Kommentar.

**Sie wurden per Mutationsprobe gegengeprüft:** Die behobenen Fehler wurden
absichtlich wieder eingebaut, um zu sehen, ob die Tests sie fangen. Dabei fiel
auf, dass einer aus dem **falschen Grund** grün war: Die Tagesgrenzen-Regel war
in seinem Aufbau von der Dauergrenze verdeckt, weil `now` mittags lag. Er ist
repariert und schreibt seine eigenen Vorbedingungen jetzt mit fest. Ein Test,
der nicht fehlschlagen kann, ist Dekoration — das prüft man einmal, oder man
weiß es nicht.

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

## Dokumentation

| Wo | Was |
|---|---|
| `Kalli/Resources/HILFE.md` | Bedienung — wird **in der App** unter Einstellungen → Hilfe angezeigt |
| `Kalli/Resources/RECHTLICHES.md` | Lizenz, Datenschutz, Gewährleistung — ebenfalls in der App |
| `CHANGELOG.md` | Änderungen je Version — in der App unter „Änderungen" |

Diese drei Dateien liegen **als Dateien im App-Bundle**, nicht als Zeichenketten
im Quelltext. `make build` spiegelt das CHANGELOG bei jedem Durchlauf frisch,
die Versionsnummer liest die App aus der `Info.plist`.

Der Grund ist eine teuer bezahlte Erfahrung aus Tippi: Eine Hilfe, die im Code
steht, driftet — sie ist eine Kopie, und Kopien veralten. Dort hing sie an einem
Tag fünf Versionen hinterher.

### Das Doku-Gate

`make install` läuft nicht, wenn die Doku dem Code hinterherhinkt:

```bash
bash scripts/docs-gate.sh
```

Geprüft wird, was maschinell prüfbar ist — nicht, ob die Prosa gut ist:

1. Existieren `CHANGELOG.md`, `README.md`, `LICENSE`, `HILFE.md`, `RECHTLICHES.md`?
2. Kennt das CHANGELOG die Version aus `project.yml`?
3. Wurden Swift-Dateien geändert, seit die Doku zuletzt angefasst wurde?
4. Stimmt das CHANGELOG im Bundle mit dem im Repo überein?

Bewusst übergehen geht — aber nur laut, und die Begründung landet in der Ausgabe:

```bash
DOCS_WAIVER="nur Formatierung" make install
```

Beim allerersten Lauf hat das Gate sofort eine fehlende `LICENSE` gefunden, die
beim Umbenennen des Projekts verloren gegangen war.

## Installieren auf einem zweiten Mac

Ohne Xcode, ohne Anmeldung, ohne geklontes Repo.

**Im Browser:** [neuestes Release](https://github.com/miwixyz/Kalli/releases/latest)
→ ZIP laden → doppelklicken → `Kalli.app` nach *Programme* ziehen.

**Auf der Kommandozeile:**

```bash
gh release download --repo miwixyz/Kalli --pattern '*.zip'   # ohne Tag = neuestes
ditto -x -k Kalli-*.zip . && mv Kalli.app /Applications/ && open /Applications/Kalli.app
```

> **Hier steht bewusst keine Versionsnummer.** Sie stand hier, und sie war nach
> drei Releases falsch — obwohl die Hausregel „README im selben Commit wie das
> Release" existiert. Eine Anleitung, die bei jedem Release von Hand
> nachgezogen werden muss, wird irgendwann nicht nachgezogen. `gh release
> download` ohne Tag nimmt das neueste; `Kalli-*.zip` passt auf jede Version.

> **`ditto`, nicht `unzip`.** `unzip` zerstört die Bundle-Metadaten eines
> signierten `.app`; Gatekeeper meldet danach „a sealed resource is missing or
> invalid" und die App sieht beschädigt aus, obwohl das Release einwandfrei ist.
> Ein Doppelklick im Finder ist ebenfalls sicher — das Archivierungsprogramm
> macht es richtig.

Das Asset ist mit **Developer ID signiert und notarisiert** — Gatekeeper lässt es
ohne Rechtsklick-Umweg starten. macOS fragt einmal nach Kalender- und
Erinnerungszugriff, danach nicht mehr: TCC bindet die Zustimmung an die
Code-Signatur, und die bleibt über Releases hinweg stabil.

Das Asset ist **ohne Anmeldung** ladbar — gegengeprüft mit `curl` ohne Token
gegen das anonym geladene Bundle: `accepted · source=Notarized Developer ID`.

## Release bauen

```bash
make release-dry-run    # Vorbedingungen zeigen, nichts bauen
make release            # signieren, notarisieren, GitHub-Release
make release PUBLISH=0  # alles außer der Veröffentlichung
```

Voraussetzungen auf dem Mac, der released: Developer-ID-Zertifikat im
Schlüsselbund und ein `notarytool`-Profil (Standard `tippi-notary`, anders über
`NOTARY_PROFILE=...`). Anlegen mit `xcrun notarytool store-credentials`.

Das Skript prüft **vor** dem Bauen, ob Zertifikat und Profil vorhanden sind, ob
der Baum sauber ist, ob das CHANGELOG die Version kennt und ob **alle Tests
bestehen** — und **nach** dem Bauen, ob wirklich mit Developer ID signiert wurde, ob das Hardened Runtime
aktiv ist, ob Apple die Notarisierung angenommen hat, ob das Ticket angeheftet
ist und ob Gatekeeper die App akzeptiert. Zum Schluss fragt es GitHub, ob das
Asset tatsächlich dort liegt. Ein lokal erfolgreicher Ablauf sagt nichts
darüber, was veröffentlicht ist.

## Aktualisieren

Kalli aktualisiert sich über **Sparkle** — aber nur, wenn du es erlaubst.

- **Ab Werk aus.** Beim ersten Mal fragt Sparkle, ob automatisch gesucht werden
  darf. Sagst du nein, gibt es keinen Netzwerkzugriff.
- **Von Hand** jederzeit über den Knopf **„Updates“** unten im Popover.
- **Findet die automatische Prüfung ein Update**, öffnet Kalli kein Fenster
  (das läge bei einer Menüleisten-App hinter anderen Apps), sondern meldet es
  sanft: eine Mitteilung und der Knopf zeigt **„Update X“**. Ein Klick auf
  eines von beiden öffnet das Update-Fenster vorn. Seit 0.4.9.
- **Zwei Signaturen** werden geprüft, bevor etwas ersetzt wird: die
  EdDSA-Signatur des Archivs gegen den in der App eingebauten öffentlichen
  Schlüssel, und Apples Developer-ID-Signatur. Schlägt eine fehl, bricht
  Sparkle ab.
- Der **Appcast liegt im Repo** (`appcast.xml`), nicht in einem Gist: Jede
  Änderung daran ist damit ein öffentlicher, datierter Commit — die billigste
  Manipulationserkennung, die zu haben ist.

Auf dem Entwicklungs-Mac weiterhin: `git pull && make install`.

Vollständiger Sicherheitsentwurf — Datenflussdiagramm, STRIDE je
Vertrauensgrenze, Missbrauchsfälle, verworfene Alternativen und die bewusst
getragenen Restrisiken — in
[`docs/AUTO-UPDATE-DESIGN.md`](docs/AUTO-UPDATE-DESIGN.md).

## Lizenz

MIT — siehe [LICENSE](LICENSE). Rechtliche Hinweise und Datenschutz stehen in
`Kalli/Resources/RECHTLICHES.md` und in der App unter Einstellungen → Hilfe →
Rechtliches.

**Kurz zum Datenschutz:** Kein Server, keine Analyse, keine Kennungen. Kalender
werden nur gelesen; bei Erinnerungen wird ausschließlich das
Erledigt-Kennzeichen gesetzt. Gespeichert werden nur die eigenen Einstellungen.

**Genau ein Netzwerkzugriff:** die Update-Prüfung bei GitHub — ab Werk **aus**,
beim ersten Mal wird gefragt. GitHub sieht dabei IP-Adresse und installierte
Version, nichts darüber hinaus.

**Eine Ausnahme, benannt statt versteckt:** Sind Systemmitteilungen
eingeschaltet (ab Werk **aus**), gibt Kalli Titel und Uhrzeit des Termins an
macOS weiter — und damit an Mitteilungszentrale und möglicherweise den
Sperrbildschirm. Alles bleibt auf dem Gerät. Vollständig in
`Kalli/Resources/RECHTLICHES.md`.
