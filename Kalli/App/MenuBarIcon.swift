import AppKit

/// Zeichnet Kallis Menüleisten-Symbol: ein Kalenderblatt mit der heutigen Zahl.
///
/// Warum gezeichnet statt SF Symbol: `calendar` sieht aus wie jede andere
/// Kalender-App. Die Tageszahl im Blatt macht das Symbol unverwechselbar **und**
/// nützlich — das Datum ist ablesbar, auch wenn der Textteil ausgeschaltet ist.
///
/// Warum ein Template-Image: macOS färbt es selbst passend zur Menüleiste ein,
/// hell wie dunkel, und behandelt die Hervorhebung beim Anklicken korrekt. Eine
/// eigene Farbwahl würde in genau einem der beiden Modi falsch aussehen.
enum MenuBarIcon {

    /// Kalenderblatt mit `day` als Zahl. Ergebnis ist bereits ein Template-Image.
    static func image(day: Int) -> NSImage {
        let size = NSSize(width: 17, height: 16)

        let image = NSImage(size: size, flipped: false) { rect in
            let line: CGFloat = 1.2
            // Unten etwas Luft lassen, oben Platz für die Ringe.
            let body = NSRect(
                x: rect.minX + line / 2,
                y: rect.minY + line / 2,
                width: rect.width - line,
                height: rect.height - line - 2.5
            )

            NSColor.black.setStroke()
            NSColor.black.setFill()

            // Blatt
            let frame = NSBezierPath(roundedRect: body, xRadius: 2.6, yRadius: 2.6)
            frame.lineWidth = line
            frame.stroke()

            // Zwei Ringe oben — das Detail, das ein Kalenderblatt von einem
            // beliebigen Rechteck unterscheidet.
            for dx in [body.width * 0.3, body.width * 0.7] {
                let ring = NSBezierPath(rect: NSRect(
                    x: body.minX + dx - 0.6, y: body.maxY - 0.5, width: 1.2, height: 2.6
                ))
                ring.fill()
            }

            // Tageszahl
            let text = "\(day)"
            let fontSize: CGFloat = text.count > 1 ? 8.5 : 9.5
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
                .foregroundColor: NSColor.black,
            ]
            let measured = text.size(withAttributes: attributes)
            text.draw(
                at: NSPoint(
                    x: body.midX - measured.width / 2,
                    // Optischer Mittelpunkt liegt etwas unter dem geometrischen,
                    // weil oben die Ringe sitzen.
                    y: body.midY - measured.height / 2 - 0.8
                ),
                withAttributes: attributes
            )
            return true
        }

        image.isTemplate = true
        return image
    }
}
