import SwiftUI

/// Farbe, in der die Tageszahl eines hervorgehobenen Wochentags im Monatsraster steht
/// (Michael, 2026-10-12: „jeder Donnerstag soll die Farbe rot haben").
///
/// Bewusst eine feste Auswahl statt freier Farbwahl: Systemfarben passen sich Hell und
/// Dunkel an und bleiben auf dem Glas lesbar. **Kein Gelb** — als Schrift auf hellem
/// Grund kaum zu lesen.
enum HighlightColor: String, CaseIterable, Identifiable {
    case red, orange, green, blue, purple, pink

    var id: String { rawValue }

    var title: String {
        switch self {
        case .red: "Rot"
        case .orange: "Orange"
        case .green: "Grün"
        case .blue: "Blau"
        case .purple: "Lila"
        case .pink: "Rosa"
        }
    }

    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .green: .green
        case .blue: .blue
        case .purple: .purple
        case .pink: .pink
        }
    }
}
