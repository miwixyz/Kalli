# Rechtliches

## Wer

Kalli wird entwickelt von **Michael Wildenauer**, München.
Kontakt: mw@cinesocial.de

## Lizenz

Kalli steht unter der **MIT-Lizenz**. Der vollständige Text liegt als `LICENSE`
im Quelltext-Verzeichnis.

Kurz: Nutzung, Änderung und Weitergabe sind erlaubt, auch kommerziell, solange
Urheberhinweis und Lizenztext erhalten bleiben. Die Software wird **ohne jede
Gewährleistung** bereitgestellt.

## Datenschutz

**Kein Server, keine Analyse, keine Absturzberichte an Dritte, keine Werbung,
keine Kennungen.** Es gibt genau **einen** Netzwerkzugriff, und der ist unten
vollständig beschrieben: die Update-Prüfung.

> Bis Version 0.3.1 stand hier „Kalli sendet nichts". Mit der eingebauten
> Update-Funktion (ab 0.4.0) wäre dieser Satz **falsch** geworden. Er ist
> ersetzt, nicht relativiert.

Was Kalli liest:

| Quelle | Zugriff | Zweck |
|---|---|---|
| Kalender (EventKit) | **nur lesen** | Termine im Raster und in der Tagesliste anzeigen |
| Erinnerungen (EventKit) | lesen **und** Erledigt-Kennzeichen setzen | Aufgaben anzeigen und abhaken |
| Mitteilungen (macOS) | **schreiben**, nur wenn du sie einschaltest | Hinweis vor einem Termin |
| GitHub (Netz) | **abrufen**, nur für Updates | Nachsehen, ob eine neuere Fassung vorliegt |

**Was geschrieben wird — vollständig:** ausschließlich das Erledigt-Kennzeichen
einer Erinnerung, und nur wenn du das Häkchen anklickst. Kalli legt nichts an,
benennt nichts um, verschiebt nichts und **löscht nichts** — weder Termine noch
Erinnerungen noch Kalender.

Was Kalli speichert: die eigenen Einstellungen in den macOS-UserDefaults unter
`com.kalli.app` — welche Kalender ausgeblendet sind, das Datumsformat, die
Schalter. **Keine Termininhalte.**

### Eine Ausnahme, die du kennen musst: Systemmitteilungen

Ist **„Systemmitteilung vor dem Termin"** eingeschaltet (ab Werk **aus**), gibt
Kalli den **Titel und die Uhrzeit** des Termins an macOS weiter, damit die
Mitteilung erscheinen kann. Folgen, die man wissen sollte:

- macOS **speichert** die geplante Mitteilung bis zur Auslieferung.
- Nach der Auslieferung steht sie in der **Mitteilungszentrale**.
- Je nach deinen macOS-Einstellungen erscheint der Titel auf dem
  **Sperrbildschirm** — also sichtbar, ohne den Mac zu entsperren.

Das bleibt vollständig auf dem Gerät und geht an keinen Server. Es ist aber der
einzige Fall, in dem ein Termininhalt Kalli verlässt — deshalb steht er hier und
nicht im Kleingedruckten. Wer das nicht will, lässt den Schalter aus; dann
entstehen keine Mitteilungen. Wer ihn will, aber keine Titel auf dem
Sperrbildschirm: macOS-Einstellungen → Mitteilungen → Kalli → **Vorschau
anzeigen: Wenn entsperrt**.

Die Mitteilungs-Berechtigung wird **erst beim Einschalten** erfragt, nie beim
Start, und kann jederzeit in den Systemeinstellungen entzogen werden.

### Der einzige Netzwerkzugriff: die Update-Prüfung

Kalli kann nachsehen, ob eine neuere Fassung vorliegt. Dazu ruft es zwei
Adressen bei GitHub ab:

- `raw.githubusercontent.com` — eine kleine Textdatei mit der neuesten
  Versionsnummer
- `github.com` — nur wenn du ein Update installierst: die Programmdatei selbst

**Was GitHub dabei sieht**, wie bei jedem Aufruf einer Webadresse: deine
**IP-Adresse**, den Zeitpunkt und einen Programmkenner, aus dem sich die
installierte Version ablesen lässt. Kalli sendet **nichts darüber hinaus** —
keine Kennung, keine Kalenderdaten, keine Statistik. Es gibt keinen Server von
Michael Wildenauer; GitHub ist die Bezugsquelle, nicht ein Auswertungsdienst.
Was GitHub mit Abrufprotokollen tut, regeln GitHubs eigene
Datenschutzbestimmungen.

**Ab Werk ist die automatische Suche AUS.** Beim ersten Mal fragt Kalli, ob es
selbständig nachsehen darf — sagst du nein, findet **kein** Netzwerkzugriff
statt, außer du drückst den Knopf „Nach Updates suchen" von Hand. Die
Entscheidung lässt sich jederzeit ändern.

**Wie sichergestellt ist, dass ein Update echt ist:** Jedes Update trägt zwei
unabhängige Signaturen — eine Signatur des Archivs mit einem Schlüssel, dessen
öffentlicher Teil in Kalli eingebaut ist, und Apples Developer-ID-Signatur.
Beide werden geprüft, **bevor** irgendetwas ersetzt wird. Schlägt eine fehl,
bricht Kalli ab. Eine untergeschobene Datei wird nicht installiert, sondern
abgelehnt.

**Kein Doppel-Alarm:** Kalli meldet nur Termine, die im Kalender keinen eigenen
Alarm tragen.

Alle Daten bleiben auf dem Gerät. Der Zugriff auf Kalender und Erinnerungen
wird von macOS verwaltet und kann jederzeit in den Systemeinstellungen unter
*Datenschutz & Sicherheit* entzogen werden.

## Keine Gewährleistung

Kalli ist ein privates Werkzeug, kein Produkt mit Supportzusage. Es kann Fehler
enthalten, Termine falsch darstellen oder unerwartet beenden.

**Verlasse dich für wichtige Termine nicht allein auf Kalli.** Maßgeblich sind
immer die Kalender- und die Erinnerungen-App von Apple. Kalli ist im
Wesentlichen eine Ansicht darauf; die einzigen Änderungen, die es vornimmt, sind
das Abhaken einer Erinnerung auf deinen Klick hin, das Planen von
Systemmitteilungen und das Installieren eines Updates — die letzten beiden nur,
falls eingeschaltet bzw. von dir bestätigt.

**Verlasse dich für wichtige Termine auch nicht allein auf Kallis Hinweise.**
Eine Mitteilung kann ausbleiben, wenn der Mac aus ist, schläft, „Nicht stören"
aktiv ist oder die Berechtigung entzogen wurde.

## Verwendete Fremdsoftware

**Eine Komponente:** **Sparkle** (MIT-Lizenz) für die Update-Funktion.
Urheberhinweis und vollständiger Lizenztext liegen in
`THIRD-PARTY-LICENSES.md` — im Quelltext-Verzeichnis **und in der App** unter
Einstellungen → Hilfe → Fremdcode. Das ausgelieferte Sparkle-Framework bringt
selbst keine Lizenzdatei mit; Kalli führt sie deshalb mit, weil die Lizenz das
für Auslieferungen verlangt.

Sonst ausschließlich Apples eigene Frameworks (SwiftUI, AppKit, EventKit,
UserNotifications, ServiceManagement).

> Bis Version 0.3.1 stand hier „Keine". Das war bis dahin richtig.

## Marken

**Calendr** und **Dato** werden in der Dokumentation als Vergleich genannt.
Beide sind Werke ihrer jeweiligen Urheber und stehen in keiner Verbindung zu
Kalli. Kalli enthält keinen Code aus diesen Projekten.

macOS, EventKit und Liquid Glass sind Marken bzw. Technologien der Apple Inc.
