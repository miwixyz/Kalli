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

**Kalli sendet nichts.** Es gibt keinen Server, keine Analyse, keine
Absturzberichte an Dritte, keine Werbung, keine Kennungen.

Was Kalli liest:

| Quelle | Zugriff | Zweck |
|---|---|---|
| Kalender (EventKit) | **nur lesen** | Termine im Raster und in der Tagesliste anzeigen |
| Erinnerungen (EventKit) | **nur lesen** | Aufgaben in der Tagesliste anzeigen |

Was Kalli speichert: ausschließlich die eigenen Einstellungen in den macOS-
UserDefaults unter `com.kalli.app` — welche Kalender ausgeblendet sind, das
Datumsformat, die Schalter. **Keine Termininhalte.**

Alle Daten bleiben auf dem Gerät. Der Zugriff auf Kalender und Erinnerungen
wird von macOS verwaltet und kann jederzeit in den Systemeinstellungen unter
*Datenschutz & Sicherheit* entzogen werden.

## Keine Gewährleistung

Kalli ist ein privates Werkzeug, kein Produkt mit Supportzusage. Es kann Fehler
enthalten, Termine falsch darstellen oder unerwartet beenden.

**Verlasse dich für wichtige Termine nicht allein auf Kalli.** Maßgeblich sind
immer die Kalender- und die Erinnerungen-App von Apple — Kalli ist nur eine
Ansicht darauf und ändert dort nichts.

## Verwendete Fremdsoftware

Keine. Kalli nutzt ausschließlich Apples eigene Frameworks (SwiftUI, AppKit,
EventKit, ServiceManagement). Es sind **keine externen Pakete** eingebunden,
also auch keine fremden Lizenzbedingungen zu beachten.

## Marken

**Calendr** und **Dato** werden in der Dokumentation als Vergleich genannt.
Beide sind Werke ihrer jeweiligen Urheber und stehen in keiner Verbindung zu
Kalli. Kalli enthält keinen Code aus diesen Projekten.

macOS, EventKit und Liquid Glass sind Marken bzw. Technologien der Apple Inc.
