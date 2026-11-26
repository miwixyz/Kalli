import AppKit
import OSLog
import SwiftUI

/// Faktor, mit dem das Tagesblatt gerade gezeichnet wird: die Textgröße, auf den Bildschirm
/// begrenzt (`DeskPad.fitScale`). Der Controller setzt ihn, die Ansichten lesen ihn statt
/// `Preferences.layoutScale`, damit Fenster und Inhalt dieselbe Größe haben.
@MainActor @Observable
final class DeskPadScale {
    var value: Double = 1
}

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
    private var shownStyle: DeskPadStyle?
    private let fit = DeskPadScale()
    private var screenObservers: [NSObjectProtocol] = []

    init(prefs: Preferences, store: CalendarStore) {
        self.prefs = prefs
        self.store = store
    }

    func start() {
        apply()
        observe()
        // Bildschirm angesteckt, abgesteckt, Auflösung geändert: Größe neu an den Platz anpassen.
        screenObservers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.apply() }
        })
    }

    /// `withObservationTracking` meldet nur die nächste Änderung — danach neu anmelden.
    private func observe() {
        withObservationTracking {
            _ = prefs.deskPadEnabled
            _ = prefs.deskPadStyle
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
        if shownStyle != prefs.deskPadStyle { install(prefs.deskPadStyle, in: panel) }
        resize(panel)
        keepOnScreen(panel)
        panel.orderFront(nil)
        // Messpunkt: „eingeschaltet“ und „sichtbar“ sind zwei Aussagen.
        Self.log.notice("Schreibtischblatt: an, sichtbar \(panel.isVisible, privacy: .public), Rahmen \(NSStringFromRect(panel.frame), privacy: .public), Ebene \(panel.level.rawValue, privacy: .public), Faktor \(self.fit.value, privacy: .public)")
    }

    /// Setzt die Ansicht für das gewählte Aussehen ein. **Schatten:** Bei undurchsichtigem Inhalt
    /// (Glas-Blatt) kommt er vom Fenster, nie aus SwiftUI: Ein `.shadow` am Rand der Ansicht wird an der
    /// Fenstergrenze rechteckig abgeschnitten und zeichnet einen grauen Kasten (Michael 2026-11-15).
    /// Bei halbtransparentem Glas (Papierblatt) wird der Fensterschatten dagegen gepunktet; dort
    /// zeichnet die Ansicht ihn selbst, kleiner als der transparente Fensterrand.
    private func install(_ style: DeskPadStyle, in panel: NSPanel) {
        shownStyle = style
        switch style {
        case .paper:
            // Halbtransparentes Glas: Der Fensterschatten wird gepunktet, die Ansicht zeichnet ihn selbst.
            panel.hasShadow = false
            panel.contentView = NSHostingView(rootView: PaperPadView()
                .environment(prefs).environment(store).environment(fit).tint(Theme.accent))
        case .glass:
            panel.hasShadow = true
            panel.contentView = NSHostingView(rootView: DeskPadView()
                .environment(prefs).environment(store).environment(fit).tint(Theme.accent))
        case .punkti:
            panel.hasShadow = true
            panel.contentView = NSHostingView(rootView: PunktiPadView()
                .environment(prefs).environment(store).environment(fit).tint(Theme.accent))
        }
        // Form erst nach dem ersten Zeichnen neu berechnen, sonst gilt der Schatten der leeren Fläche.
        DispatchQueue.main.async { [weak panel] in panel?.invalidateShadow() }
    }

    /// Feste Größe je Aussehen, mit der Textgröße skaliert, aber höchstens so groß, wie der
    /// Bildschirm des Fensters Platz hat (Ränder wie in `keepOnScreen`). Die obere linke Ecke
    /// bleibt stehen.
    private func resize(_ panel: NSPanel) {
        let base = prefs.deskPadStyle.windowSize
        if let area = screen(of: panel)?.visibleFrame {
            fit.value = DeskPad.fitScale(base: base, scale: prefs.layoutScale,
                                         available: CGSize(width: area.width - 48, height: area.height - 16))
        } else {
            fit.value = prefs.layoutScale
        }
        let size = NSSize(width: (base.width * fit.value).rounded(), height: (base.height * fit.value).rounded())
        guard panel.frame.size != size else { return }
        var frame = panel.frame
        frame.origin.y += frame.height - size.height
        frame.size = size
        panel.setFrame(frame, display: true)
    }

    /// Hält das Fenster ganz auf einem Bildschirm. Nötig, weil die gemerkte Position aus einer
    /// anderen Größe oder von einem abgesteckten Bildschirm stammen kann (gemessen 2026-11-15:
    /// Papierblatt 372 breit, Position für 320 gemerkt, rechts 28 pt über dem Rand).
    private func keepOnScreen(_ panel: NSPanel) {
        guard let area = screen(of: panel)?.visibleFrame else { return }
        var frame = panel.frame
        frame.origin.x = min(max(frame.origin.x, area.minX + 24), area.maxX - frame.width - 24)
        frame.origin.y = min(max(frame.origin.y, area.minY + 8), area.maxY - frame.height - 8)
        if frame != panel.frame { panel.setFrame(frame, display: true) }
    }

    private func applyAfterDrag() async {
        while NSEvent.pressedMouseButtons != 0 {
            try? await Task.sleep(for: .milliseconds(200))
        }
        apply()
    }

    /// Bildschirm, auf dem das Fenster (zum größten Teil) liegt; sonst der erste.
    private func screen(of panel: NSPanel) -> NSScreen? {
        let overlap = { (screen: NSScreen) -> CGFloat in
            let part = screen.frame.intersection(panel.frame)
            return part.isNull ? 0 : part.width * part.height
        }
        return NSScreen.screens.max { overlap($0) < overlap($1) }.flatMap { overlap($0) > 0 ? $0 : nil }
            ?? NSScreen.screens.first
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
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.title = "Kalli Tagesblatt"
        #if DEBUG
        // Zum Ansehen und für Messungen mit Mausereignissen: vor allen Fenstern statt dahinter.
        if ProcessInfo.processInfo.arguments.contains("-tagesblattVorne") { panel.level = .floating }
        #endif
        if !panel.setFrameUsingName(Self.frameName) {
            let area = (NSScreen.screens.first ?? NSScreen.main)?.visibleFrame ?? .zero
            panel.setFrameTopLeftPoint(NSPoint(x: area.maxX - panel.frame.width - 40, y: area.maxY - 24))
        }
        panel.setFrameAutosaveName(Self.frameName)
        #if DEBUG
        // Messpunkt (2026-11-26): `-tagesblattBildschirm N` legt das Blatt oben links auf Bildschirm N.
        // Erst nach dem Autosave-Namen: Der setzt die gemerkte Position und überschriebe sonst diese.
        let args = ProcessInfo.processInfo.arguments
        if let flag = args.firstIndex(of: "-tagesblattBildschirm"), flag + 1 < args.count,
           let index = Int(args[flag + 1]), NSScreen.screens.indices.contains(index) {
            let area = NSScreen.screens[index].visibleFrame
            panel.setFrameTopLeftPoint(NSPoint(x: area.minX + 40, y: area.maxY - 8))
        }
        #endif
        // Auf einen anderen Bildschirm gezogen: dort neu einpassen, aber erst nach dem Loslassen —
        // eine Größenänderung mitten im Ziehen springt unter dem Zeiger weg.
        screenObservers.append(NotificationCenter.default.addObserver(
            forName: NSWindow.didChangeScreenNotification, object: panel, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.applyAfterDrag() }
        })
        return panel
    }
}
