import AppKit
import OSLog
import SwiftUI

/// Hält das Fenster des Aufgaben-Pop-ups (`TaskDigest`): randloses Glasfenster oben links auf dem
/// Hauptbildschirm, über allen Fenstern und auf allen Spaces. Es wird **nicht** zum Tastaturfenster
/// und aktiviert Kalli nicht — die laufende Arbeit behält den Fokus. Ziehbar am Hintergrund; die
/// gewählte Stelle bleibt gespeichert.
@MainActor
final class TaskDigestPresenter {

    private static let log = Logger(subsystem: "com.kalli.app", category: "aufgaben")

    private var panel: NSPanel?
    private var host: NSView?
    private var moveObserver: NSObjectProtocol?
    private var placedCorner: NSPoint?
    private let defaults: UserDefaults

    static let positionKey = "taskDigestTopLeft"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    var isOpen: Bool { panel != nil }

    func show(_ view: TaskDigestView, prefs: Preferences, store: CalendarStore) {
        close()
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        // NSPanel verschwindet ab Werk, sobald die App nicht mehr aktiv ist (siehe Vollbild-Hinweis).
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.title = "Kalli Aufgaben heute"
        let host = NSHostingView(rootView: view.environment(prefs).environment(store).tint(Theme.accent))
        panel.contentView = host
        self.panel = panel
        self.host = host
        panel.setContentSize(host.fittingSize)
        let areas = NSScreen.screens.map(\.visibleFrame)
        let saved = defaults.string(forKey: Self.positionKey).map(NSPointFromString)
        let corner = Self.topLeft(saved: saved, size: panel.frame.size, areas: areas)
        panel.setFrameTopLeftPoint(corner)
        placedCorner = corner
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: panel, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.rememberPosition() }
        }
        panel.orderFrontRegardless()
        DispatchQueue.main.async { [weak panel] in panel?.invalidateShadow() }
        // Messpunkt: „gezeigt" und „sichtbar" sind zwei Aussagen. Kein Titel, keine Inhalte.
        Self.log.notice("Aufgaben-Fenster: sichtbar \(panel.isVisible, privacy: .public), Rahmen \(NSStringFromRect(panel.frame), privacy: .public), Tastaturfenster \(panel.isKeyWindow, privacy: .public)")
    }

    /// Nach dem Abhaken wird die Liste kürzer: Höhe anpassen, die obere linke Ecke bleibt stehen.
    func refit() {
        guard let panel, let host else { return }
        let size = host.fittingSize
        guard size != panel.frame.size else { return }
        var frame = panel.frame
        frame.origin.y += frame.height - size.height
        frame.size = size
        panel.setFrame(frame, display: true, animate: false)
        panel.invalidateShadow()
    }

    /// Obere linke Ecke des Fensters. Ab Werk oben **links** auf dem Hauptbildschirm — oben rechts
    /// liegen die Mitteilungen von macOS. Eine von Hand gewählte Stelle gilt weiter, solange das
    /// Fenster dort noch ganz auf einen Bildschirm passt (sonst: Bildschirm abgesteckt → ab Werk).
    nonisolated static func topLeft(saved: NSPoint?, size: NSSize, areas: [NSRect]) -> NSPoint {
        if let saved {
            let frame = NSRect(x: saved.x, y: saved.y - size.height, width: size.width, height: size.height)
            if areas.contains(where: { $0.contains(frame) }) { return saved }
        }
        let area = areas.first ?? .zero
        return NSPoint(x: area.minX + 16, y: area.maxY - 12)
    }

    /// Nur eine echte Verschiebung wird gemerkt — nicht die Stelle, an die `show` das Fenster setzt.
    private func rememberPosition() {
        guard let panel else { return }
        let corner = NSPoint(x: panel.frame.minX, y: panel.frame.maxY)
        guard corner != placedCorner else { return }
        placedCorner = corner
        defaults.set(NSStringFromPoint(corner), forKey: Self.positionKey)
    }

    func close() {
        if let moveObserver { NotificationCenter.default.removeObserver(moveObserver) }
        moveObserver = nil
        panel?.orderOut(nil)
        panel = nil
        host = nil
    }
}

/// Inhalt des Aufgaben-Pop-ups: die heute fälligen, offenen Erinnerungen zum Abhaken, darunter
/// „In 1 Std. wieder" und „Schließen". Formensprache wie Tagesblatt und Popover.
///
/// Laden und Abhaken kommen als Closures herein, damit die Ansicht in der Bild-Testkopie mit
/// Beispieldaten läuft, ohne EventKit zu berühren.
struct TaskDigestView: View {
    @Environment(Preferences.self) private var prefs
    @Environment(CalendarStore.self) private var store

    @State var items: [AgendaItem]
    let load: @MainActor () async -> [AgendaItem]
    /// Hakt ab und gibt eine Fehlermeldung zurück, wenn das Häkchen nicht angekommen ist.
    let toggle: @MainActor (AgendaItem) async -> String?
    let onSnooze: () -> Void
    let onClose: () -> Void
    let onResize: () -> Void

    @State private var toggleError: String?
    @State private var busy: Set<String> = []

    /// Mehr Zeilen werden nur gezählt — das Fenster soll ein Hinweis bleiben, keine zweite Liste.
    static let maxShown = 8

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "HH:mm"
        return f
    }()

    private var scale: Double { prefs.layoutScale }

    var body: some View {
        VStack(alignment: .leading, spacing: 12 * scale) {
            header
            VStack(alignment: .leading, spacing: 8 * scale) {
                ForEach(items.prefix(Self.maxShown)) { row($0) }
                if items.count > Self.maxShown {
                    Text("und \(items.count - Self.maxShown) weitere")
                        .font(Theme.font(Theme.Size.itemTime, scale))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 24 * scale)
                }
            }
            if let toggleError {
                Text(toggleError)
                    .font(Theme.font(Theme.Size.hint, scale))
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            actions
        }
        .padding(16 * scale)
        .frame(width: 340 * scale, alignment: .leading)
        .movesWindow()
        .glassSurface(in: RoundedRectangle(cornerRadius: 24 * scale, style: .continuous))
        // Anderswo abgehakt oder neu angelegt: Liste nachziehen.
        .task(id: store.revision) { await reload() }
        .onChange(of: items.count) { onResize() }
        .onChange(of: toggleError) { onResize() }
    }

    private var header: some View {
        HStack(spacing: 8 * scale) {
            Image(systemName: "checklist")
                .font(.system(size: 13 * scale, weight: .semibold))
                .foregroundStyle(Theme.accent)
            Text("Heute fällig")
                .font(Theme.font(Theme.Size.monthTitle, scale, weight: .semibold))
            Spacer()
            Text(verbatim: items.count == 1 ? "1 Aufgabe" : "\(items.count) Aufgaben")
                .font(Theme.font(Theme.Size.itemTime, scale))
                .foregroundStyle(.secondary)
        }
    }

    private func row(_ item: AgendaItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8 * scale) {
            Button { complete(item) } label: {
                Image(systemName: busy.contains(item.id) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15 * scale))
                    .foregroundStyle(Color(red: item.color.r, green: item.color.g, blue: item.color.b))
            }
            .buttonStyle(.plain)
            .disabled(busy.contains(item.id))
            .help("Erledigt")
            .accessibilityLabel(Text(verbatim: "\(item.title) erledigen"))

            if item.isUrgent {
                Image(systemName: "exclamationmark")
                    .font(.system(size: 10 * scale, weight: .heavy))
                    .foregroundStyle(.red)
            }
            // `verbatim`: Der Titel kommt aus Erinnerungsdaten (auch geteilte Listen) und wird
            // nie als Markdown gedeutet.
            Text(verbatim: item.title)
                .font(Theme.font(Theme.Size.itemTitle, scale))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Text(verbatim: item.timeLabel(using: Self.timeFormatter))
                .font(Theme.font(Theme.Size.itemTime, scale))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    /// Familien-Glasknopf statt `.glass`: Das Fenster wird nie zum Tastaturfenster, und Apples
    /// Stil zeichnet Knöpfe in einem nicht aktiven Fenster ausgegraut (gemessen 2026-11-17).
    private var actions: some View {
        HStack(spacing: 8 * scale) {
            // Immer da. Reicht die Stunde über Mitternacht, wirkt der Knopf wie „Schließen":
            // Es wären dann nicht mehr die Aufgaben von heute (`TaskDigest.snoozeDate`).
            Button(action: onSnooze) {
                Label("In 1 Std. wieder", systemImage: "zzz")
            }
            Spacer()
            Button("Schließen", action: onClose)
                .help("Für heute schließen")
        }
        .font(Theme.font(Theme.Size.itemTitle, scale, weight: .medium))
        .buttonStyle(.familyGlass(.capsule, size: 28 * scale))
        .padding(.top, 2 * scale)
    }

    private func reload() async {
        items = await load()
        if items.isEmpty { onClose() }
    }

    private func complete(_ item: AgendaItem) {
        busy.insert(item.id)
        Task {
            toggleError = await toggle(item)
            busy.remove(item.id)
            guard toggleError == nil else { return }
            await reload()
        }
    }
}
