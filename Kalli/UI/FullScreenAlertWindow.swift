import AppKit
import OSLog
import SwiftUI

/// Randloses Panel, das Tastatureingaben annehmen darf (Esc/Return).
/// Ein randloses Fenster wird von AppKit sonst nie „key".
private final class AlertPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Esc. Ein unsichtbarer SwiftUI-Knopf mit `.cancelAction` kam nicht an
    /// (gemessen 2026-09-29, Return über den sichtbaren Knopf dagegen schon).
    var onCancel: (() -> Void)?
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

/// Legt den Vollbild-Hinweis über **alle** Bildschirme, auch über Vollbild-Apps und
/// alle Spaces. Schließen auf einem Bildschirm schließt alle.
@MainActor
final class FullScreenAlertPresenter {

    private var panels: [NSPanel] = []
    private var items: [AgendaItem] = []

    /// Neue Termine kommen zu einem offenen Hinweis dazu, statt ein zweites Fenster
    /// darüberzulegen.
    func show(_ new: [AgendaItem]) {
        for item in new where !items.contains(where: { $0.id == item.id }) {
            items.append(item)
        }
        items.sort { ($0.start ?? .distantFuture) < ($1.start ?? .distantFuture) }
        present()
    }

    private func present() {
        panels.forEach { $0.orderOut(nil) }
        panels = NSScreen.screens.map(makePanel)
        panels.forEach { $0.orderFrontRegardless() }
        (panels.first { $0.screen == NSScreen.main } ?? panels.first)?.makeKey()
        // Messpunkt: Ein Hinweis, der still nicht erscheint, ist schlimmer als keiner.
        let visible = panels.filter(\.isVisible).count
        let key = panels.contains(where: \.isKeyWindow)
        Self.log.notice("Vollbild gezeigt: \(self.items.count, privacy: .public) Termin(e), \(NSScreen.screens.count, privacy: .public) Bildschirm(e), \(visible, privacy: .public)/\(self.panels.count, privacy: .public) Fenster sichtbar, Tastatur: \(key, privacy: .public)")
    }

    private static let log = Logger(subsystem: "com.kalli.app", category: "vollbild")

    private func makePanel(for screen: NSScreen) -> NSPanel {
        // `.nonactivatingPanel`: Das Fenster wird „key" und nimmt Esc/Return an, ohne dass
        // Kalli die aktive App werden muss. macOS verweigert einer Menüleisten-App das
        // ungefragte Aktivieren (gemessen 2026-09-29: frontmost blieb false, Tasten kamen
        // nicht an). Gleiches Muster wie Spotlight.
        let panel = AlertPanel(contentRect: screen.frame,
                               styleMask: [.borderless, .nonactivatingPanel],
                               backing: .buffered, defer: false)
        panel.becomesKeyOnlyIfNeeded = false
        panel.onCancel = { [weak self] in self?.close() }
        panel.setFrame(screen.frame, display: false)
        panel.level = .screenSaver
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary,
                                    .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isReleasedWhenClosed = false
        // NSPanel verschwindet ab Werk, sobald die App nicht mehr aktiv ist. Gemessen
        // 2026-09-29: 2/2 Fenster sichtbar, Sekunden später 0. Der Hinweis soll aber
        // stehen bleiben, bis man ihn schließt.
        panel.hidesOnDeactivate = false

        // Kein fester Look: Hell/Dunkel folgt dem System, das Glas kommt aus der
        // SwiftUI-Ansicht (dieselbe `glassSurface` wie im Popover).
        let host = NSHostingView(rootView: FullScreenAlertView(
            items: items,
            onClose: { [weak self] in self?.close() },
            onOpen: { [weak self] url in self?.open(url) }
        ))
        // Die SwiftUI-Ansicht liegt in einer schlichten Hülle, nicht direkt als
        // Fensterinhalt. Direkt als Inhalt verschluckte sie Esc, bevor
        // `cancelOperation` das Fenster erreichte (gemessen 2026-09-29).
        let container = NSView()
        host.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(host)
        NSLayoutConstraint.activate([
            host.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.topAnchor.constraint(equalTo: container.topAnchor),
            host.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])
        panel.contentView = container
        return panel
    }

    private func close() {
        panels.forEach { $0.orderOut(nil) }
        panels = []
        items = []
    }

    /// Zweite Prüfung direkt vor dem Öffnen, falls ein Link auf anderem Weg in ein
    /// `AgendaItem` gelangt ist.
    private func open(_ url: URL) {
        if MeetingLink.isOpenable(url) {
            NSWorkspace.shared.open(url)
        }
        close()
    }
}

/// Inhalt des Hinweises.
///
/// **Aufbau (Michael, 2026-09-29):** Die untere Bildschirmhälfte ist eine Liquid-Glass-
/// Fläche, die obere ein Verlauf, der oben durchsichtig beginnt. Die Arbeit bleibt
/// sichtbar, der Termin steht unübersehbar davor. Hell/Dunkel folgt dem System.
///
/// **Formensprache wie im Popover:** Kalenderfarbpunkt, Kapsel im Kalli-Blau mit feinem
/// Rand (wie `UpcomingBanner`), Glas über `glassSurface`, Schrift über `Theme.font`.
struct FullScreenAlertView: View {
    let items: [AgendaItem]
    let onClose: () -> Void
    let onOpen: (URL) -> Void

    /// Weitere gleichzeitige Termine als Karten. Mehr wird nur gezählt.
    private static let maxShown = 4

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "HH:mm"
        return f
    }()

    /// Tönung für den Verlauf: Schiefer-Hintergrundton (hell bzw. dunkel) statt reinem
    /// Schwarz/Weiß (Design-System 0.6.0).
    private var veil: Color { FamilyTheme.backgroundTop }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {
                // Über den ganzen Bildschirm, oben durchsichtig, zur Mitte hin dichter.
                // Reicht bis unter das Glas, damit keine Kante zwischen beiden entsteht.
                LinearGradient(
                    stops: [
                        .init(color: veil.opacity(0.0), location: 0.0),
                        .init(color: veil.opacity(0.18), location: 0.30),
                        .init(color: veil.opacity(0.45), location: 0.55),
                        .init(color: veil.opacity(0.55), location: 1.0)
                    ],
                    startPoint: .top, endPoint: .bottom
                )

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    content(now: context.date)
                        .frame(maxWidth: 820, alignment: .leading)
                        .padding(.horizontal, 56)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(height: geo.size.height / 2)
                .glassSurface(in: UnevenRoundedRectangle(
                    topLeadingRadius: 44, topTrailingRadius: 44, style: .continuous
                ))
            }
        }
        .ignoresSafeArea()
    }

    // MARK: - Inhalt

    @ViewBuilder
    private func content(now: Date) -> some View {
        if let first = items.first {
            VStack(alignment: .leading, spacing: 28) {
                header(first, now: now)
                mainTitle(first)

                let others = Array(items.dropFirst().prefix(Self.maxShown))
                if !others.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(others) { item in otherCard(item, now: now) }
                        if items.count - 1 > Self.maxShown {
                            Text("und \(items.count - 1 - Self.maxShown) weitere")
                                .font(Theme.font(13, 1))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                actions(first)
            }
        }
    }

    private func header(_ first: AgendaItem, now: Date) -> some View {
        HStack(alignment: .center) {
            statusCapsule(FullScreenAlertView.status(start: first.start, now: now))
            Spacer()
            Text(verbatim: Self.timeFormatter.string(from: now))
                .font(Theme.font(22, 1, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private func mainTitle(_ first: AgendaItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                colorDot(first, size: 14)
                // `verbatim`: Der Titel kommt aus Kalenderdaten und wird nie als
                // Markdown oder Lokalisierungsschlüssel gedeutet.
                Text(verbatim: first.title)
                    .font(Theme.font(44, 1, weight: .semibold))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(verbatim: first.timeLabel(using: Self.timeFormatter))
                .font(Theme.font(20, 1))
                .foregroundStyle(.secondary)
                .padding(.leading, 28)
        }
    }

    private func actions(_ first: AgendaItem) -> some View {
        HStack(spacing: 12) {
            if let link = first.link, let host = link.host {
                Button { onOpen(link) } label: {
                    // Der echte Host, nicht ein Linktext aus der Einladung: So
                    // sieht man immer, wohin der Knopf führt.
                    Label("Link öffnen · \(host)", systemImage: "video")
                        .padding(.horizontal, 6)
                        .foregroundStyle(Theme.onAccent)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.accent)
            }
            Button(action: onClose) {
                Text("Schließen").padding(.horizontal, 10)
            }
            .buttonStyle(.glass)
            .keyboardShortcut(.defaultAction)
            Spacer()
            Text("esc oder return schließt")
                .font(Theme.font(Theme.Size.hint + 2, 1))
                .foregroundStyle(.tertiary)
        }
        .controlSize(.extraLarge)
    }

    /// Wie `UpcomingBanner` im Popover: Kalli-Blau, zarte Fläche, feiner Rand.
    private func statusCapsule(_ text: String) -> some View {
        Label {
            Text(verbatim: text).monospacedDigit()
        } icon: {
            Image(systemName: "bell.fill")
        }
        .font(Theme.font(15, 1, weight: .semibold))
        .foregroundStyle(Theme.accent)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background {
            Capsule()
                .fill(Theme.accent.opacity(0.12))
                .overlay { Capsule().strokeBorder(Theme.accent.opacity(0.25), lineWidth: 0.8) }
        }
    }

    private func colorDot(_ item: AgendaItem, size: CGFloat) -> some View {
        Circle()
            .fill(Color(red: item.color.r, green: item.color.g, blue: item.color.b))
            .frame(width: size, height: size)
    }

    /// Weitere Termine zur selben Zeit — gleiche Karte wie `UpcomingBanner`.
    private func otherCard(_ item: AgendaItem, now: Date) -> some View {
        HStack(spacing: 10) {
            colorDot(item, size: 9)
            Text(verbatim: item.title)
                .font(Theme.font(Theme.Size.bannerTitle + 3, 1, weight: .semibold))
                .lineLimit(1)
            Text(verbatim: item.timeLabel(using: Self.timeFormatter))
                .font(Theme.font(Theme.Size.itemTime + 3, 1))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            if let link = item.link, let host = link.host {
                Button("Link öffnen · \(host)") { onOpen(link) }
                    .buttonStyle(.plain)
                    .font(Theme.font(Theme.Size.itemTime + 3, 1, weight: .medium))
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background {
            RoundedRectangle(cornerRadius: Theme.cardRadius + 3, style: .continuous)
                .fill(Theme.accent.opacity(0.10))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.cardRadius + 3, style: .continuous)
                        .strokeBorder(Theme.accent.opacity(0.22), lineWidth: 0.8)
                }
        }
    }

    /// „Beginnt in 3 Min." · „Beginnt gleich" · „Hat vor 2 Min. begonnen".
    nonisolated static func status(start: Date?, now: Date) -> String {
        guard let start else { return "" }
        let seconds = start.timeIntervalSince(now)
        if seconds > 60 {
            return "Beginnt in \(Int((seconds / 60).rounded(.up))) Min."
        }
        if seconds > -60 {
            return "Beginnt gleich"
        }
        return "Hat vor \(Int((-seconds / 60).rounded(.down))) Min. begonnen"
    }
}
