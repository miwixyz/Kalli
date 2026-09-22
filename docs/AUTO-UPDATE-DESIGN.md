# Auto-Update (Sparkle) — Sicherheitsentwurf

**Stand:** 2026-09-22 · **Status:** entworfen, noch nicht umgesetzt

Dieses Dokument entsteht **vor** der ersten Zeile Code. Ein Auto-Updater ist ein
Code-Ausführungspfad: Die App lädt selbständig ein Archiv und ersetzt sich damit.
Wird die Signaturprüfung falsch verdrahtet, ist das keine Anzeigefehler-Klasse
mehr, sondern eine Fernübernahme. Deshalb steht der Entwurf hier, mit den
verworfenen Alternativen und den bewusst getragenen Restrisiken.

---

## 0. Der Punkt, der schwerer wiegt als die Technik

`RECHTLICHES.md` sagt heute: **„Kalli sendet nichts. Es gibt keinen Server, keine
Analyse, keine Kennungen."**

Mit Sparkle ist dieser Satz **falsch**. Kalli würde regelmäßig
`raw.githubusercontent.com` kontaktieren und dabei — wie jeder HTTP-Aufruf —
IP-Adresse, User-Agent und damit implizit die installierte Version an GitHub
übermitteln. Kein Tracking, keine Kennung, aber **Netzwerkverkehr**, wo bisher
keiner war.

Das ist dieselbe Fehlerklasse, die am 2026-09-22 beim Audit als 🟠 gefunden
wurde (Mitteilungen gaben Termintitel an macOS weiter, während die Zusage
„keine Termininhalte" behauptete). Sie darf sich nicht wiederholen.

**Entschieden:** Die Datenschutz-Zusage wird **im selben Commit** wie die
Sparkle-Integration umgeschrieben, nicht danach. Ohne diese Änderung wird nicht
ausgeliefert.

---

## 1. Datenfluss und Vertrauensgrenzen

```
                          ┆ Vertrauensgrenze: Netz
[Kalli.app]  ──GET────────┆──→ [raw.githubusercontent.com/…/appcast.xml]
  │                       ┆         (unsignierter Transportkanal, TLS)
  │  prüft EdDSA-Signatur ┆
  ├──GET────────────────── ┆──→ [github.com/…/releases/download/…zip]
  │                       ┆
  ├─ prüft EdDSA-Signatur des Archivs gegen SUPublicEDKey (im App-Bundle)
  ├─ prüft Code-Signatur (Developer ID) des entpackten Bundles
  └─ ersetzt sich selbst  ← CODE-AUSFÜHRUNG

[Mac des Entwicklers] ─── signiert ──→ Archiv + Appcast
  └─ privater EdDSA-Schlüssel: Login-Schlüsselbund, NIE im Repo
```

Drei Grenzüberschreitungen, drei Kontrollpunkte:

| Grenze | Was sie trägt | Kontrolle |
|---|---|---|
App → Appcast | XML, vollständig angreifergesteuert, falls der Kanal fällt | EdDSA-Signatur **pro Archiv**; TLS; kein `eval`-Pfad in XML |
App → Release-Asset | ZIP, ausführbarer Inhalt | EdDSA-Signatur **und** Developer-ID-Signatur, beide von Sparkle geprüft |
Entwickler-Mac → Kanal | Signatur + Veröffentlichung | Schlüsselbund; GitHub-Konto mit 2FA |

---

## 2. Abhängigkeit: Sparkle

**Pick, nicht write** — eindeutig. Ein Updater ist Krypto plus
Protokollimplementierung plus selbstersetzender Prozess. Genau die Kategorie,
für die „pick, don't write" gilt. Eigenbau wäre die schlechteste Option dieses
Entwurfs.

**Wartungssignal, am 2026-09-22 gemessen** (nicht behauptet):

| | |
|---|---|
Sterne / Forks | 9.736 / 1.141 |
Letzter Push | 2026-09-22 (derselbe Tag) |
Letztes Release | 2.10.0 am 2026-09-13 |
Archiviert | nein |
`SECURITY.md` im 2.x-Branch | **404** — nicht vorhanden |
Lizenz laut GitHub-API | **`NOASSERTION`** — nicht automatisch erkannt |

**Zwei offene Punkte, ausdrücklich als solche notiert:**

1. Keine `SECURITY.md`. Sparkle hat eine GHSA-Historie und reagiert auf CVEs,
   aber es gibt keine erklärte Richtlinie. Kein Ausschlussgrund bei diesem
   Reifegrad und dieser Verbreitung — aber es ist ein Signal, das man kennt.
2. `NOASSERTION` heißt nicht „keine Lizenz", sondern „GitHub konnte sie nicht
   zuordnen". Sparkle ist MIT mit Hinweisen auf mitgelieferte Komponenten
   anderer Lizenz. **Vor dem Ausliefern zu prüfen und in `RECHTLICHES.md`
   zu nennen**, weil Kalli selbst MIT ist.

**Entschieden — Versionsfestlegung:** `exactVersion: 2.10.0`, **nicht**
`from: 2.0.0`.

*Verworfen:* `from:`-Bereich, wie Tippi ihn benutzt. Für eine Anwendung (nicht
Bibliothek) gilt exakte Festlegung plus Lockfile. Bei `from: 2.0.0` entscheidet
der Auflösungszeitpunkt, welche Version in einen Release wandert — bei einem
Updater ist das die falsche Stelle für Zufall.

**Entschieden — `Package.resolved` wird versioniert.** Tippi tut das nicht; die
Sparkle-Version dort ist deshalb nicht reproduzierbar. Das wird hier nicht
geerbt. (Separater Merkposten für Tippi.)

**Installationszeit-Ausführung:** SPM hat keine `postinstall`-Haken. Sparkle
liefert jedoch Hilfsprogramme (`generate_appcast`, `sign_update`) mit, die auf
dem Entwickler-Mac laufen — siehe Abschnitt 4.

**Transitive Tiefe:** Sparkle zieht keine weiteren SPM-Abhängigkeiten. Damit
bleibt Kalli bei **einer** direkten und **null** transitiven Abhängigkeiten.

---

## 3. Schlüsselverwaltung

| Datum | Klassifikation | Wo |
|---|---|---|
Privater EdDSA-Schlüssel | **Secret** (Signierschlüssel) | Login-Schlüsselbund, Sparkle-Standardslot |
Öffentlicher EdDSA-Schlüssel | öffentlich | `SUPublicEDKey` im App-Bundle |

**Entschieden — der vorhandene Schlüssel wird wiederverwendet**, derselbe wie
bei Tippi. Nicht aus Bequemlichkeit, sondern weil Sparkles Werkzeug es
ausdrücklich so vorgibt: *„You only need one signing key, no matter how many
apps you embed Sparkle in."* Gegengeprüft: `generate_keys` ohne Argumente
überschreibt einen vorhandenen Schlüssel **nicht**, es gibt ihn nur aus.

*Verworfen:* ein eigenes Schlüsselpaar für Kalli. Begründung für die Ablehnung,
damit sie nachvollziehbar bleibt: Der Schlüssel allein liefert nichts aus — ein
Angreifer braucht **zusätzlich** Schreibzugriff auf den Appcast-Kanal, und die
Kanäle beider Apps sind getrennt (verschiedene Repos). Der realistische
Kompromittierungsfall ist „Entwickler-Mac übernommen", und dann sind beide
Schlüssel weg, egal wie viele es sind. Ein zweiter Schlüssel hätte hier Aufwand
ohne Wirkung erzeugt.

**Nie im Repo, nie in CI.** Es gibt keine CI für Releases; sie laufen von Hand
auf dem Entwickler-Mac. Das ist hier ein Vorteil: kein CI-Geheimnis, das
auslaufen kann.

---

## 4. Appcast: Erzeugung und Hosting

**Entschieden — der Appcast liegt im Repo** (`appcast.xml` auf `main`), von
Sparkle über `https://raw.githubusercontent.com/miwixyz/Kalli/main/appcast.xml`
geladen.

*Verworfen:* ein GitHub-Gist, wie Tippi es benutzt. Ein Gist hat keine
Prüfhistorie im Projekt — eine Änderung am Appcast ist dort unsichtbar. Im Repo
ist **jede** Änderung ein Commit: Wer je einen manipulierten Appcast
veröffentlichen wollte, hinterlässt einen öffentlichen, datierten Eintrag. Das
ist die billigste Manipulationserkennung, die zu haben ist.

*Verworfen:* Hosting auf dem Hostinger-VPS. War die Notlösung für das private
Repo. Mit der Veröffentlichung entfallen Grund und Pflegeaufwand.

**Entschieden — die Werkzeuge kommen aus der festgelegten Sparkle-Version**,
nicht aus `~/Developer/sparkle-tools/`. Tippi nutzt dort handplatzierte Binaries
unbekannter Herkunft und schluckt ihre Fehler mit `2>/dev/null`. Beides gehört
auf die Refuse-List:

- Werkzeug-Herkunft = dieselbe Version, die auch in der App steckt
- **Kein `2>/dev/null`** auf dem Signierschritt. Ein Appcast, der still nicht
  signiert wurde, ist ein Release, das niemand installieren kann — oder
  schlimmer, eines das ungeprüft durchgeht.
- Exit-Code wird geprüft, die Signatur des erzeugten Appcasts wird
  **gegengelesen**, bevor veröffentlicht wird.

---

## 5. Voreinstellungen

**Entschieden — `SUEnableAutomaticChecks` wird NICHT gesetzt.** Sparkle fragt
dann beim ersten Mal, ob automatisch gesucht werden darf. Das entspricht der
Hausregel, die schon für Bildschirm-OCR (Tippi) und die Systemmitteilungen
(Kalli 0.2.0) galt: *Was von sich aus in den Tag hineinredet oder das Netz
benutzt, wird erteilt, nicht geerbt.*

*Verworfen:* `SUEnableAutomaticChecks = true`, wie Tippi es setzt. Bei Kalli
wäre das eine Netzverbindung ab Werk in einer App, die bisher **keine** hatte.

**Entschieden — zusätzlich ein Menüeintrag „Nach Updates suchen"** im Popover.
Ohne ihn gibt es keinen Weg, eine Prüfung willentlich auszulösen.

---

## 6. STRIDE je Grenze

### App → Appcast (Netz)

- **Spoofing:** Kann der Kanal übernommen werden? TLS gegen GitHub; ein
  Angreifer bräuchte GitHub-Schreibzugriff oder eine gebrochene CA. → Die
  Signatur pro Archiv ist die eigentliche Verteidigung, nicht TLS.
- **Tampering:** Manipulierter Appcast ohne den Schlüssel → Sparkle lehnt das
  Archiv ab. Manipulierter Appcast **mit** gültiger Signatur eines *echten,
  älteren* Archivs = Downgrade-Angriff. → Sparkle verweigert Versionen ≤
  installiert; zusätzlich ist der Appcast im Repo öffentlich einsehbar.
- **Information disclosure:** Der Abruf offenbart IP und Version gegenüber
  GitHub. → **Nicht vermeidbar, wird offengelegt** (Abschnitt 0).
- **DoS:** Appcast nicht erreichbar → Sparkle scheitert still am Hintergrundlauf.
  Akzeptiert: Kalli bleibt benutzbar, nur ohne Update-Hinweis.

### App → Release-Asset (Netz)

- **Tampering:** Bösartiges ZIP → EdDSA-Prüfung **und** Developer-ID-Prüfung.
  Zwei unabhängige Vertrauensanker; ein Angreifer bräuchte beide Schlüssel.
- **Elevation of privilege:** Das Ersetzen der App ist der Übernahmepunkt.
  Gegenprüfung in der Umsetzung: Sparkle darf **nicht** mit erhöhten Rechten
  laufen, kein Installer-Skript, kein `pkg` — nur App-Ersetzung.

### Entwickler-Mac → Kanal

- **Spoofing/Elevation:** Wer den Mac hat, hat Schlüssel *und* GitHub-Token.
  → **Schlimmster Einzelfall dieses Entwurfs.** Gegenmaßnahmen sind
  organisatorisch: 2FA am GitHub-Konto, FileVault, Schlüsselbund-Sperre.
- **Repudiation:** Jede Veröffentlichung hinterlässt Tag, Release und
  Appcast-Commit. Nicht fälschungssicher, aber nachvollziehbar.

---

## 7. Missbrauchs-Zwillinge

| Anwendungsfall | Missbrauchs-Zwilling | Antwort im Entwurf |
|---|---|---|
„Kalli sucht nach Updates" | Angreifer stellt einen Appcast bereit, der auf sein Archiv zeigt | EdDSA-Signatur; ohne den Schlüssel wird nichts installiert |
„Kalli installiert ein Update" | Angreifer liefert ein **echtes, älteres** Archiv mit bekannter Lücke | Downgrade-Verweigerung durch Sparkle; Appcast öffentlich einsehbar |
„Michael veröffentlicht ein Release" | Jemand mit Repo-Zugriff, aber ohne Schlüssel, veröffentlicht ein Asset | Signaturprüfung schlägt fehl; Nutzer bekommen kein Update statt eines falschen |
„Nutzer prüft manuell" | Wiederholtes Auslösen als Lastangriff auf GitHub | Vernachlässigbar; GitHub drosselt selbst |

---

## 8. Negativraum — was wird implizit unterstellt?

1. **GitHub wird als Verteilkanal vertraut.** Fällt GitHub aus, gibt es keine
   Updates; wird ein GitHub-Konto übernommen, fehlt dem Angreifer noch der
   Signierschlüssel. Bewusst getragen.
2. **Der Login-Schlüsselbund wird als sicher unterstellt.** Bei entsperrtem Mac
   plus Schadcode mit Nutzerrechten ist der Schlüssel erreichbar. Bewusst
   getragen; Alternative wäre ein Hardware-Token, unverhältnismäßig für eine
   Menüleisten-App mit zwei Installationen.
3. **Sparkles Signaturprüfung wird als korrekt unterstellt.** Das ist der
   eigentliche Vertrauenstransfer dieser Abhängigkeit — und der Grund, warum
   „selbst bauen" die schlechtere Wahl wäre.
4. **Bei einem Vorfall** lässt sich reagieren: Release löschen, Appcast-Commit
   zurücknehmen, Schlüssel neu erzeugen und mit einem neuen `SUPublicEDKey`
   ausliefern. Der letzte Schritt erreicht Altinstallationen **nicht**
   automatisch — sie müssten von Hand neu installieren. Bewusst getragen und
   hier notiert, damit es im Vorfall nicht überrascht.

---

## 9. Restrisiken, bewusst getragen

| Risiko | Warum getragen |
|---|---|
Übernahme des Entwickler-Macs kompromittiert Schlüssel und Kanal | Kein verhältnismäßiger Gegenentwurf für zwei Installationen |
Abruf offenbart IP + Version gegenüber GitHub | Unvermeidbar bei jedem Update-Mechanismus; wird offengelegt statt verschwiegen |
Kein `SECURITY.md` bei Sparkle | Reife und Verbreitung wiegen das auf; CVE-Historie wird über SCA beobachtet |
Schlüsselwechsel erreicht Altinstallationen nicht | Bekannt, im Vorfall-Ablauf notiert |

---

## 10. Abnahmekriterien vor dem Ausliefern

- [ ] Sparkle exakt festgelegt, `Package.resolved` versioniert
- [ ] `SUPublicEDKey` im Bundle, privater Schlüssel **nicht** im Repo
      (`rafter secrets` über den Baum **und** die Historie)
- [ ] `SUFeedURL` ist `https`, Appcast im Repo, Signatur nach dem Erzeugen
      gegengelesen
- [ ] `SUEnableAutomaticChecks` **nicht** gesetzt; Menüeintrag vorhanden
- [ ] Sparkle-Lizenz geprüft und in `RECHTLICHES.md` genannt
- [ ] **`RECHTLICHES.md`, `HILFE.md` und README: „Kalli sendet nichts" ersetzt**
      — im selben Commit
- [ ] `make test` grün, `make release` mit allen Gates
- [ ] Update einmal **echt** durchgespielt: ältere Version installieren, Update
      anbieten lassen, installieren, Version gegenprüfen

Erst wenn der letzte Punkt gemessen ist, gilt das Feature als vorhanden.
`rafter-code-review` beim Umsetzen.
