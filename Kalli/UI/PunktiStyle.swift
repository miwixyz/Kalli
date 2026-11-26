import SwiftUI

// Glas-Look aus Punkti (Michael 2026-11-26: „Das Design bitte wie Punkti“), für das Widget und das
// Aussehen „Punkti“ des Tagesblatts, damit Kalli
// neben Punktis Widgets auf dem Schreibtisch aus einem Guss wirkt. Kopiert aus
// `~/Coding/punkti/Shared/PunktiClock.swift` (Stand 2026-11-26, gleicher Urheber), gekürzt auf den
// Standard-Hintergrund. Ändert sich dort etwas am Look, hier nachziehen.

/// Dunkler Verlauf mit drei weichen Farbflecken (Punkti „Standard“).
struct PunktiGlassBackground: View {
    var body: some View {
        GeometryReader { g in
            let s = max(g.size.width, g.size.height)
            ZStack {
                LinearGradient(colors: [Color(red: 0.03, green: 0.06, blue: 0.17), Color(red: 0.10, green: 0.03, blue: 0.19)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().fill(Color(red: 0.12, green: 0.45, blue: 1.0).opacity(0.55))
                    .frame(width: s * 0.75).blur(radius: s * 0.13).offset(x: -s * 0.25, y: -s * 0.22)
                Circle().fill(Color(red: 0.78, green: 0.22, blue: 0.88).opacity(0.45))
                    .frame(width: s * 0.65).blur(radius: s * 0.13).offset(x: s * 0.28, y: s * 0.30)
                Circle().fill(Color(red: 0.0, green: 0.80, blue: 0.80).opacity(0.28))
                    .frame(width: s * 0.40).blur(radius: s * 0.10).offset(x: s * 0.32, y: -s * 0.30)
            }
            .frame(width: g.size.width, height: g.size.height)
            .clipped()
        }
    }
}

/// Glasscheibe: milchiger Verlauf, heller Rand mit Lichtkante oben links, Glanz oben, weicher Schatten.
struct PunktiGlassDisc: View {
    var body: some View {
        GeometryReader { g in
            let d = min(g.size.width, g.size.height)
            Circle()
                .fill(LinearGradient(colors: [.white.opacity(0.20), .white.opacity(0.05)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Circle().strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.75), .white.opacity(0.04), .white.opacity(0.35)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: max(1, d * 0.006)))
                .overlay(alignment: .top) {
                    Ellipse()
                        .fill(LinearGradient(colors: [.white.opacity(0.10), .clear], startPoint: .top, endPoint: .bottom))
                        .frame(width: d * 0.70, height: d * 0.22)
                        .blur(radius: d * 0.03)
                        .padding(.top, d * 0.02)
                }
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.40), radius: d * 0.04, y: d * 0.025)
                .frame(width: d, height: d)
        }
    }
}

/// Punktering: ein Punkt je Tag des Monats, heute leuchtet mit Schweif, vergangene Tage schwach gefüllt,
/// jeder siebte größer (wie Punktis Datum-Widget).
struct PunktiDotRing: View {
    let position: Double
    let color: Color
    var count: Int = 30
    var emphasisEvery: Int = 7
    var tailLength: Double = 3

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width, size.height)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = s / 2 - s * 0.07
            let n = Double(count)
            func point(_ i: Double) -> CGPoint {
                let angle = i / n * 2 * .pi - .pi / 2
                return CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            }
            func dot(_ p: CGPoint, _ r: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
            }
            for i in 0..<count {
                let big = i % emphasisEvery == 0
                var d = position - Double(i)
                if d < 0 { d += n }
                let t = d < tailLength ? pow(1 - d / tailLength, 2) : 0
                var base = big ? 0.40 : 0.16
                if Double(i) < position { base = max(base, big ? 0.55 : 0.38) }
                let r = s * (big ? 0.015 : 0.0095) * (1 + 0.9 * t)
                ctx.fill(dot(point(Double(i)), r), with: .color(color.opacity(base + (1 - base) * t)))
            }
            let head = point(position)
            ctx.drawLayer { layer in
                layer.addFilter(.blur(radius: s * 0.022))
                layer.fill(dot(head, s * 0.03), with: .color(color.opacity(0.85)))
            }
            ctx.fill(dot(head, s * 0.0185), with: .color(color))
        }
    }
}

/// Eine LED-Ziffer (7 Segmente); nicht leuchtende Segmente bleiben als Geist sichtbar.
struct PunktiSegmentDigit: View {
    /// `nil` = leere Stelle (nur Geister-Segmente).
    let digit: Int?
    let color: Color

    // a oben, b oben rechts, c unten rechts, d unten, e unten links, f oben links, g Mitte.
    private static let masks: [[Bool]] = [
        [true, true, true, true, true, true, false],
        [false, true, true, false, false, false, false],
        [true, true, false, true, true, false, true],
        [true, true, true, true, false, false, true],
        [false, true, true, false, false, true, true],
        [true, false, true, true, false, true, true],
        [true, false, true, true, true, true, true],
        [true, true, true, false, false, false, false],
        [true, true, true, true, true, true, true],
        [true, true, true, true, false, true, true],
    ]

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            let t = w * 0.19
            let gap = t * 0.14
            let half = t / 2
            func horizontal(_ y: CGFloat) -> Path {
                var p = Path()
                let x0 = half + gap, x1 = w - half - gap
                p.move(to: CGPoint(x: x0, y: y))
                p.addLine(to: CGPoint(x: x0 + half, y: y - half))
                p.addLine(to: CGPoint(x: x1 - half, y: y - half))
                p.addLine(to: CGPoint(x: x1, y: y))
                p.addLine(to: CGPoint(x: x1 - half, y: y + half))
                p.addLine(to: CGPoint(x: x0 + half, y: y + half))
                p.closeSubpath()
                return p
            }
            func vertical(_ x: CGFloat, _ y0: CGFloat, _ y1: CGFloat) -> Path {
                var p = Path()
                let a = y0 + gap, b = y1 - gap
                p.move(to: CGPoint(x: x, y: a))
                p.addLine(to: CGPoint(x: x + half, y: a + half))
                p.addLine(to: CGPoint(x: x + half, y: b - half))
                p.addLine(to: CGPoint(x: x, y: b))
                p.addLine(to: CGPoint(x: x - half, y: b - half))
                p.addLine(to: CGPoint(x: x - half, y: a + half))
                p.closeSubpath()
                return p
            }
            let mid = h / 2
            let segments: [Path] = [
                horizontal(half), vertical(w - half, half, mid), vertical(w - half, mid, h - half),
                horizontal(h - half), vertical(half, mid, h - half), vertical(half, half, mid), horizontal(mid),
            ]
            let mask = digit.map { Self.masks[max(0, min(9, $0))] } ?? [Bool](repeating: false, count: 7)
            for (i, path) in segments.enumerated() {
                ctx.fill(path, with: .color(color.opacity(mask[i] ? 1 : 0.09)))
            }
        }
    }
}
