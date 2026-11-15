import AppKit
import SwiftUI

/// Macht eine Fläche zum Griff, an dem sich das Fenster mit der Maus verschieben lässt
/// (Tagesblatt). `isMovableByWindowBackground` und ein NSView im Hintergrund greifen hier nicht:
/// SwiftUI fängt den Klick ab (gemessen 2026-11-15: weder Ziehen am Brettrand noch ein
/// Hintergrund-NSView bekamen ein `mouseDown`). Deshalb startet die Ziehgeste selbst das
/// Verschieben mit `performDrag`. Knöpfe, Liste und das Blatt-Ziehen darüber behalten Vorrang,
/// weil ihre Gesten tiefer in der Hierarchie liegen.
private struct MovesWindow: ViewModifier {
    @State private var moving = false

    func body(content: Content) -> some View {
        content.gesture(
            DragGesture(minimumDistance: 2, coordinateSpace: .global)
                .onChanged { _ in
                    guard !moving, let event = NSApp.currentEvent, let window = event.window else { return }
                    moving = true
                    // Läuft, bis die Maustaste losgelassen wird.
                    window.performDrag(with: event)
                }
                .onEnded { _ in moving = false }
        )
    }
}

extension View {
    func movesWindow() -> some View { modifier(MovesWindow()) }
}
