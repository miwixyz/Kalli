#if DEBUG
import AppKit
import EventKit
import OSLog
import ScreenCaptureKit
import Security
import SwiftUI

/// Befehlskanal der Bild-Testkopie (docs/SECURE-DESIGN.md K1), nur Debug-Build und nur mit Kennung
/// `dev.mwlr.kalli.bild`. Befehle kommen über `debug.sock` (`DebugSocketServer`: Audit-Token gegen
/// `DebugCommand.ctlRequirement` vor dem ersten Byte). Antworten liegen als `Antworten/<id>.json`, Bilder als
/// `Bilder/<id>-<fenster>.png` im eigenen Ordner `~/Library/Application Support/Kalli Bild` (0700).
///
/// Kalli hat keine eigenen Fenster – Einstellungen und Hilfe stehen im Popover. Für ein Bild öffnet die Kopie
/// deshalb ein eigenes Fenster mit denselben Ansichten in Popover-Breite und nimmt nur dieses auf.
@MainActor
final class DebugBridge {
    private static let log = Logger(subsystem: "com.kalli.app", category: "debug")
    private static var current: DebugBridge?

    private let prefs: Preferences
    private let store: CalendarStore
    private let label: MenuBarLabel
    private let directory: URL
    private var server: DebugSocketServer?
    private var windows: [String: NSWindow] = [:]

    private init(prefs: Preferences, store: CalendarStore, label: MenuBarLabel, directory: URL) {
        self.prefs = prefs
        self.store = store
        self.label = label
        self.directory = directory
    }

    static var directory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Kalli Bild", isDirectory: true)
    }

    static func start(prefs: Preferences, store: CalendarStore, label: MenuBarLabel) {
        guard BildKopie.isActive, current == nil, let dir = directory,
              DebugSocketServer.prepareDirectory(dir) else { return log.error("Befehlskanal aus: Ordner") }
        var req: SecRequirement?
        guard SecRequirementCreateWithString(DebugCommand.ctlRequirement as CFString, [], &req) == errSecSuccess,
              let req else { return log.error("Befehlskanal aus: Anforderung ungültig") }
        let bridge = DebugBridge(prefs: prefs, store: store, label: label, directory: dir)
        let server = DebugSocketServer(socketPath: dir.appendingPathComponent("debug.sock").path, requirement: req) { command in
            Task { @MainActor in await bridge.handle(command) }
        }
        do {
            try server.start()
            bridge.server = server
            current = bridge
            log.notice("Befehlskanal bereit")
        } catch {
            log.error("Befehlskanal aus: \(String(describing: error), privacy: .public)")
        }
    }

    private func handle(_ command: DebugCommand) async {
        var answer: [String: Any] = ["v": 1, "id": command.id]
        switch command.kind {
        case .status:
            answer["status"] = status()
        case .appearance(let mode):
            prefs.appearanceMode = switch mode {
            case "light": .light
            case "dark": .dark
            default: .system
            }
            prefs.appearanceMode.apply()
            answer["ok"] = true
        case .snapshot(let window):
            answer.merge(await snapshot(window: window, id: command.id)) { $1 }
        }
        write(answer, id: command.id)
    }

    /// Nur Zahlen und Kennungen – keine Titel, keine Inhalte.
    private func status() -> [String: Any] {
        let info = Bundle.main.infoDictionary ?? [:]
        let open = NSApp.windows.filter(\.isVisible).compactMap { w -> [String: Any]? in
            guard let id = w.identifier?.rawValue, DebugCommand.snapshotWindows.contains(id) else { return nil }
            return ["id": id, "breite": Int(w.frame.width), "hoehe": Int(w.frame.height)]
        }
        let mode = switch prefs.appearanceMode {
        case .system: "system"
        case .light: "light"
        case .dark: "dark"
        }
        return ["version": info["CFBundleShortVersionString"] as? String ?? "?",
                "kennung": Bundle.main.bundleIdentifier ?? "?",
                "bildschirmaufnahme": CGPreflightScreenCaptureAccess(),
                "modus": mode,
                "darstellung": NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? "dark" : "light",
                "kalenderzugriff": EKEventStore.authorizationStatus(for: .event).rawValue,
                "erinnerungszugriff": EKEventStore.authorizationStatus(for: .reminder).rawValue,
                "fenster": open]
    }

    /// Fenster mit derselben Ansicht wie im Popover (gleiche Breite, gleiche Umgebung).
    private func window(_ id: String) -> NSWindow {
        if let w = windows[id] { return w }
        let isHelp = id == DebugCommand.helpWindow
        let content = VStack(spacing: 12) {
            if isHelp { HelpView() } else { SettingsView() }
        }
        .padding(12)
        .frame(width: (prefs.showWeekNumbers ? 396 : 360) * prefs.layoutScale)
        .environment(prefs)
        .environment(store)
        .environment(label)
        .tint(Theme.accent)
        let controller = NSHostingController(rootView: content)
        let w = NSWindow(contentViewController: controller)
        w.styleMask = [.titled, .closable]
        w.title = isHelp ? "Hilfe" : "Einstellungen"
        w.identifier = NSUserInterfaceItemIdentifier(id)
        w.isReleasedWhenClosed = false
        w.setContentSize(controller.view.fittingSize)
        w.center()
        windows[id] = w
        return w
    }

    /// Öffnet das eigene Fenster, wartet kurz und nimmt NUR dieses Fenster per ScreenCaptureKit auf.
    private func snapshot(window id: String, id answerID: String) async -> [String: Any] {
        guard CGPreflightScreenCaptureAccess() else {
            // Trägt „Kalli Bild“ in die Liste der Systemeinstellungen ein (einmalig mit Systemdialog).
            CGRequestScreenCaptureAccess()
            return ["ok": false, "fehler": "Bildschirmaufnahme nicht freigegeben – in den Systemeinstellungen erlauben, App neu starten"]
        }
        let win = window(id)
        NSApp.activate()
        win.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .milliseconds(900))
        let windowID = CGWindowID(win.windowNumber)
        let scale = win.backingScaleFactor
        let size = win.frame.size
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let scWindow = content.windows.first(where: { $0.windowID == windowID }) else {
                return ["ok": false, "fehler": "Fenster nicht in ScreenCaptureKit"]
            }
            let config = SCStreamConfiguration()
            config.width = Int(size.width * scale)
            config.height = Int(size.height * scale)
            config.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(desktopIndependentWindow: scWindow), configuration: config)
            let folder = directory.appendingPathComponent("Bilder", isDirectory: true)
            guard DebugSocketServer.prepareDirectory(folder),
                  let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
                return ["ok": false, "fehler": "Bild nicht gespeichert"]
            }
            let file = folder.appendingPathComponent("\(answerID)-\(id).png")
            try png.write(to: file, options: .atomic)
            return ["ok": true, "datei": file.path, "breite": image.width, "hoehe": image.height]
        } catch {
            return ["ok": false, "fehler": "Aufnahme: \(error.localizedDescription)"]
        }
    }

    private func write(_ answer: [String: Any], id: String) {
        let folder = directory.appendingPathComponent("Antworten", isDirectory: true)
        guard DebugSocketServer.prepareDirectory(folder),
              let data = try? JSONSerialization.data(withJSONObject: answer, options: [.sortedKeys]) else {
            return Self.log.error("Antwort nicht geschrieben")
        }
        do {
            try data.write(to: folder.appendingPathComponent("\(id).json"), options: .atomic)
        } catch {
            Self.log.error("Antwort nicht geschrieben: \(error.localizedDescription, privacy: .public)")
        }
        Self.log.notice("Befehl ausgeführt")
    }
}
#endif
