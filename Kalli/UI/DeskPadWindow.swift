import AppKit
import OSLog
import SwiftUI

/// Hält das Tagesblatt-Fenster (0.14.0): ein randloses Glas-Fenster auf Schreibtisch-Ebene, also
/// über den Symbolen und hinter allen App-Fenstern, auf allen Spaces. Ziehbar am Hintergrund;
/// die Position merkt sich AppKit unter dem Namen `KalliDeskPad`. Ein- und ausgeschaltet wird es
/// über `Preferences.deskPadEnabled` — der Controller beobachtet den Schalter selbst.
@MainActor
final class DeskPadController {

    private static let log = Logger(subsystem: "com.kalli.app", category: "schreibtischblatt")
    private static let frameName = "KalliDeskPad"

    private let prefs: Preferences
    private let store: CalendarStore
    private var panel: NSPanel?

    init(prefs: Preferences, store: CalendarStore) {
        self.prefs = prefs
        self.store = store
    }

    func start() {
        apply()
        observe()
    }

    /// `withObservationTracking` meldet nur die nächste Änderung — danach neu anmelden.
    private func observe() {
        withObservationTracking {
            _ = prefs.deskPadEnabled
            _ = prefs.layoutScale
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.apply()
                self?.observe()
            }
        }
    }

    private func apply() {
        guard prefs.deskPadEnabled else {
            panel?.orderOut(nil)
            Self.log.notice("Schreibtischblatt: aus")
            return
        }
        let panel = self.panel ?? makePanel()
        self.panel = panel
        resize(panel)
        panel.orderFront(nil)
        // Messpunkt: „eingeschaltet“ und „sichtbar“ sind zwei Aussagen.
        Self.log.notice("Schreibtischblatt: an, sichtbar \(panel.isVisible, privacy: .public), Rahmen \(NSStringFromRect(panel.frame), privacy: .public), Ebene \(panel.level.rawValue, privacy: .public)")
    }

    /// Feste Größe, mit der Textgröße skaliert; die obere linke Ecke bleibt stehen.
    private func resize(_ panel: NSPanel) {
        let size = NSSize(width: 320 * prefs.layoutScale, height: 460 * prefs.layoutScale)
        guard panel.frame.size != size else { return }
        var frame = panel.frame
        frame.origin.y += frame.height - size.height
        frame.size = size
        panel.setFrame(frame, display: true)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 460),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        // Über den Schreibtisch-Symbolen, unter jedem App-Fenster (Level 0).
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.title = "Kalli Tagesblatt"
        panel.contentView = NSHostingView(rootView: DeskPadView()
            .environment(prefs)
            .environment(store)
            .tint(Theme.accent))
        if !panel.setFrameUsingName(Self.frameName) {
            let area = (NSScreen.screens.first ?? NSScreen.main)?.visibleFrame ?? .zero
            panel.setFrameTopLeftPoint(NSPoint(x: area.maxX - 320 - 24, y: area.maxY - 24))
        }
        panel.setFrameAutosaveName(Self.frameName)
        return panel
    }
}
