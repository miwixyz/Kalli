import AppKit

/// Zeichnet Kallis Menüleisten-Symbol: die Kopf-Silhouette mit der heutigen
/// Tageszahl darin.
///
/// **Warum diese Form:** Tippi verwendet in der Leiste nicht sein Maskottchen,
/// sondern dessen *Kontur* — runder Kopf, zwei Ohren, innen das Visier. Kalli
/// übernimmt genau diese Kopfform, damit die beiden Apps nebeneinander als
/// Familie lesbar sind, und setzt an die Stelle des Visiers die Tageszahl.
/// Damit ist das Symbol zugleich Marke und Information.
///
/// Ein detailliertes Maskottchen wäre hier falsch: Bei 16–20 Punkt Kantenlänge
/// und einfarbiger Darstellung zerfällt jedes Rendering zu einem grauen Fleck.
/// Die Leiste verlangt eine Silhouette, kein Porträt.
///
/// **Template-Image:** macOS färbt es selbst passend zur Leiste ein — hell wie
/// dunkel — und behandelt die Hervorhebung beim Anklicken. Eine eigene Farbwahl
/// sähe in genau einem der beiden Modi falsch aus.
enum MenuBarIcon {

    /// Kopf-Silhouette mit `day` als Zahl. Ergebnis ist ein Template-Image.
    static func image(day: Int) -> NSImage {
        // Quadratisch, damit es auf Leisten mit und ohne Notch gleich sitzt.
        let side: CGFloat = 18
        let size = NSSize(width: side, height: side)

        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSColor.black.setStroke()

            let line: CGFloat = 1.5
            // Der Kopf sitzt etwas tiefer, damit die Ohren oben Platz haben.
            let head = NSRect(
                x: rect.minX + line / 2 + 0.6,
                y: rect.minY + line / 2,
                width: rect.width - line - 1.2,
                height: rect.height - line - 2.2
            )

            // Ohren zuerst, damit der Kopf sie sauber überdeckt.
            let earR = head.width * 0.21
            for cx in [head.minX + head.width * 0.235, head.maxX - head.width * 0.235] {
                let ear = NSBezierPath(ovalIn: NSRect(
                    x: cx - earR, y: head.maxY - earR * 0.75,
                    width: earR * 2, height: earR * 2
                ))
                ear.fill()
            }

            // Kopf als Kontur — wie bei Tippi, nicht als Fläche.
            let skull = NSBezierPath(roundedRect: head,
                                     xRadius: head.width * 0.42,
                                     yRadius: head.height * 0.42)
            skull.lineWidth = line
            skull.stroke()

            // Tageszahl im Gesichtsfeld.
            let text = "\(day)"
            let fontSize: CGFloat = text.count > 1 ? 8.0 : 9.0
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
                .foregroundColor: NSColor.black,
            ]
            let measured = text.size(withAttributes: attributes)
            text.draw(
                at: NSPoint(
                    x: head.midX - measured.width / 2,
                    y: head.midY - measured.height / 2 - 0.3
                ),
                withAttributes: attributes
            )
            return true
        }

        image.isTemplate = true
        return image
    }
}
