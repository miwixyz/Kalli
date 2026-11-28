import AppKit

/// Zeichnet Kallis Menüleisten-Symbol: ein Kalenderblatt mit der heutigen
/// Tageszahl darin.
///
/// **Warum diese Form (Richtung C, 28.11.2026):** Die Menüleistensymbole der
/// App-Familie waren mit gemeinsamer Kopf-Silhouette kaum unterscheidbar. Jede
/// App bekommt deshalb eine eigene Silhouette; Kallis ist das Kalenderblatt mit
/// zwei Ringen. Vorlage: `07 Anhänge/Brand-Characters/familie/menueleiste/kalli*.svg`
/// im Vault. Statt der drei Punkte der Vorlage steht im Blatt die Tageszahl —
/// das Symbol ist zugleich Marke und Information.
///
/// Ein detailliertes Maskottchen wäre hier falsch: Bei 16–20 Punkt Kantenlänge
/// und einfarbiger Darstellung zerfällt jedes Rendering zu einem grauen Fleck.
/// Die Leiste verlangt eine Silhouette, kein Porträt.
///
/// **Template-Image:** macOS färbt es selbst passend zur Leiste ein — hell wie
/// dunkel — und behandelt die Hervorhebung beim Anklicken. Eine eigene Farbwahl
/// sähe in genau einem der beiden Modi falsch aus.
enum MenuBarIcon {

    /// Was im Gesichtsfeld steht: die Tageszahl oder, bei laufender Zeiterfassung (0.21.0), ein Abspielzeichen
    /// bzw. zwei Pausenstriche.
    enum Face: Equatable {
        case day(Int)
        case running
        case paused
    }

    /// Kopf-Silhouette mit `day` als Zahl. Ergebnis ist ein Template-Image.
    static func image(day: Int) -> NSImage { image(face: .day(day)) }

    static func image(face: Face) -> NSImage {
        // Quadratisch, damit es auf Leisten mit und ohne Notch gleich sitzt.
        let side: CGFloat = 18
        let size = NSSize(width: side, height: side)

        // Koordinaten wie in der SVG-Vorlage (18 × 18, y nach unten); `flipped: true` übernimmt sie 1:1.
        let image = NSImage(size: size, flipped: true) { _ in
            NSColor.black.setFill()
            NSColor.black.setStroke()

            // Blatt als Kontur.
            let sheet = NSBezierPath(roundedRect: NSRect(x: 2, y: 4.4, width: 14, height: 12.2),
                                     xRadius: 3, yRadius: 3)
            sheet.lineWidth = 1.5
            sheet.stroke()

            // Kopfzeile.
            let header = NSBezierPath()
            header.move(to: NSPoint(x: 2, y: 8.8))
            header.line(to: NSPoint(x: 16, y: 8.8))
            header.lineWidth = 1.5
            header.stroke()

            // Zwei Ringe oben.
            for x in [5.8, 12.2] {
                let ring = NSBezierPath()
                ring.move(to: NSPoint(x: x, y: 2.2))
                ring.line(to: NSPoint(x: x, y: 5.6))
                ring.lineWidth = 2.2
                ring.lineCapStyle = .round
                ring.stroke()
            }

            switch face {
            case .day(let day):
                drawDay(day)
            case .running:
                let tri = NSBezierPath()
                tri.move(to: NSPoint(x: 7.7, y: 10.7))
                tri.line(to: NSPoint(x: 7.7, y: 14.7))
                tri.line(to: NSPoint(x: 11.2, y: 12.7))
                tri.close()
                tri.lineWidth = 0.7
                tri.lineJoinStyle = .round
                tri.fill()
                tri.stroke()
            case .paused:
                for x in [7.5, 10.5] {
                    let bar = NSBezierPath()
                    bar.move(to: NSPoint(x: x, y: 10.7))
                    bar.line(to: NSPoint(x: x, y: 14.7))
                    bar.lineWidth = 1.5
                    bar.lineCapStyle = .round
                    bar.stroke()
                }
            }
            return true
        }

        image.isTemplate = true
        return image
    }

    /// Tageszahl in den Rumpf unter der Kopfzeile, optisch an der Versalhöhe zentriert.
    private static func drawDay(_ day: Int) {
        let text = "\(day)"
        let font = NSFont.monospacedDigitSystemFont(ofSize: 7.0, weight: .bold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let width = text.size(withAttributes: attributes).width
        // Innenraum des Rumpfs: y 9.55 … 15.85 (Striche abgezogen). Mitte 12.5 statt rechnerisch 12.7: gemessen
        // am gerenderten Bild (2x) sitzt die Ziffer sonst 0,15 pt zu tief.
        let centerY: CGFloat = 12.5
        let baseline = centerY + font.capHeight / 2
        // `draw(at:)` setzt den oberen Rand der Zeile; im gespiegelten Kontext liegt die Grundlinie bei y + ascender.
        text.draw(at: NSPoint(x: 9 - width / 2, y: baseline - font.ascender), withAttributes: attributes)
    }
}
