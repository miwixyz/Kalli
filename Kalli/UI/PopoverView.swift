import SwiftUI

struct PopoverView: View {

    @Environment(Preferences.self) private var prefs
    @Environment(CalendarStore.self) private var store
    @Environment(MenuBarLabel.self) private var label
    @Environment(Updater.self) private var updater
    @Environment(OneThing.self) private var oneThing

    @State private var visibleMonth = Date()
    @State private var selection = Date()
    @State private var showingSettings = false
    @State private var toggleError: String?
    /// Gerade abgehakte Aufgaben. Sie bleiben kurz stehen, damit das Abhaken
    /// sichtbar wird, bevor der Filter sie entfernt.
    @State private var justCompleted: Set<String> = []
    /// Eingabezeile „Neue Erinnerung" offen (0.10.0).
    @State private var addingReminder = false
    /// Tag des letzten Öffnens. Der Zustand überlebt das Schließen (gemessen 2026-11-18):
    /// Nach einem Tageswechsel stand sonst morgens noch der gestrige Tag in der Liste.
    @State private var lastOpened = Date()
    /// Sichtbare Höhe des Bildschirms, auf dem das Popover aufgeht, und gemessene Höhen —
    /// damit die Tagesliste das Popover nicht über den Bildschirm hinaus wachsen lässt
    /// (gemessen 2026-11-18: 1.167 pt bei „Sehr groß", ein 13"-MacBook hat rund 920).
    @State private var screenHeight: CGFloat = .infinity
    @State private var totalHeight: CGFloat = 0
    @State private var listHeight: CGFloat = 0

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "de_DE")
        c.firstWeekday = 2                       // Montag
        return c
    }

    private let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "LLLL yyyy"
        return f
    }()

    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "EEEE, d. MMMM"
        return f
    }()

    var body: some View {
        // Keine Trennlinien: Luft trennt die Bereiche (macOS-26-Formensprache).
        VStack(spacing: 12) {
            header

            // „Die eine Sache" (0.7.0) — oben, weil sie der Tag ist, nicht ein Termin darin.
            if !showingSettings {
                OneThingField(scale: prefs.layoutScale)
            }

            if showingSettings {
                SettingsView()
                    .environment(prefs)
                    .environment(store)
                    .environment(label)
                    .environment(updater)
            } else if case .denied = store.access {
                accessHint
            } else {
                // Fehlt eine Berechtigung nur teilweise (z. B. Kalender ja,
                // Erinnerungen nein), funktioniert die Ansicht — und genau
                // deshalb war der Zustand bis 0.4.2 unsichtbar: Der
                // Vollbild-Hinweis hing an `.denied`, der Teilfall an nichts.
                // Eine Zeile, die nicht blockiert, aber nicht zu übersehen ist.
                if store.permissionsIncomplete {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { showingSettings = true }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "exclamationmark.circle")
                            Text("Eine Berechtigung fehlt — hier prüfen")
                                .font(Theme.font(Theme.Size.hint, prefs.layoutScale))
                        }
                        .foregroundStyle(FamilyTheme.warning)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }

                if prefs.showUpcomingBanner, let banner = bannerItem {
                    UpcomingBanner(item: banner, showProgress: prefs.showRunningProgress,
                                   scale: prefs.layoutScale)
                }
                MonthGrid(
                    month: visibleMonth,
                    selection: $selection,
                    calendar: calendar,
                    showWeekNumbers: prefs.showWeekNumbers,
                    scale: prefs.layoutScale,
                    hasItems: { store.hasItems(on: $0, calendar: calendar) },
                    highlight: { prefs.highlight(for: $0, calendar: calendar)?.color }
                )
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .familyContentCard()
                agenda
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .familyContentCard()
            }

            // Die Fehlermeldung stand bis 2026-09-22 INNERHALB der ScrollView,
            // hinter der Terminliste. Bei voller Agenda lag sie unter der Falz
            // und war nur nach Scrollen zu sehen — eine Meldung, die man
            // suchen muss, ist keine. Sie gehoert an einen festen Platz.
            if let toggleError {
                Label(toggleError, systemImage: "exclamationmark.triangle")
                    .font(Theme.font(Theme.Size.hint, prefs.layoutScale))
                    .foregroundStyle(FamilyTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            footer
        }
        .padding(12)
        .frame(width: (prefs.showWeekNumbers ? 396 : 360) * prefs.layoutScale)

        // Glas-Sprache (ab Knippi 0.7.0): lebender, deckender Verlauf statt getöntem Glas —
        // Monat und Tagesliste liegen darauf auf festen Karten, Schwebendes auf Glas (PopoverChrome.swift).
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { totalHeight = $0 }
        .popoverChrome()
        .onAppear(perform: popoverOpened)
        .task(id: visibleMonth) {
            await store.load(month: visibleMonth, calendar: calendar)
            label.update()
        }
    }

    // MARK: - Teile

    private var header: some View {
        HStack {
            Text(showingSettings
                 ? "Einstellungen"
                 : monthFormatter.string(from: visibleMonth).capitalized)
                .font(Theme.font(Theme.Size.monthTitle + 2, prefs.layoutScale, weight: .bold))
                .contentTransition(.numericText())
            Spacer()
            if !showingSettings {
                // Eine Glasgruppe statt drei Einzelknöpfe (Porter-Optik, 13.11.2026): Lichtkante
                // folgt dem Zeiger, Hover-Schatten gleitet, Drücken staucht. Neutral, nicht in der
                // Akzentfarbe — drei blaue Knöpfe waren zu laut (0.6.0-Test).
                // Runde 2 der Glas-Sprache: Die ganze Kopfzeile ist eine Glas-Insel, die Knöpfe darin
                // tragen kein eigenes Glas mehr (kein Glas auf Glas), nur den gleitenden Hover-Schatten.
                let size = 26 * prefs.layoutScale
                HStack(spacing: 1) {
                    Button { step(-1) } label: {
                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                            .frame(width: size, height: size).contentShape(Capsule())
                    }
                    .buttonStyle(.glassPress)
                    .glassGhostItem()
                    .help("Vorheriger Monat")
                    .accessibilityLabel(Text("Vorheriger Monat"))
                    Button {
                        visibleMonth = Date()
                        selection = Date()
                    } label: {
                        Text("Heute").font(Theme.font(Theme.Size.itemTime, prefs.layoutScale, weight: .medium))
                            .padding(.horizontal, size * 0.35).frame(height: size).contentShape(Capsule())
                    }
                    .buttonStyle(.glassPress)
                    .glassGhostItem()
                    .help("Zurück zum heutigen Tag")
                    Button { step(1) } label: {
                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                            .frame(width: size, height: size).contentShape(Capsule())
                    }
                    .buttonStyle(.glassPress)
                    .glassGhostItem()
                    .help("Nächster Monat")
                    .accessibilityLabel(Text("Nächster Monat"))
                }
                .frame(height: size + 4)
                .glassGhostHost()
                .foregroundStyle(FamilyTheme.textPrimary)
            }
        }
        .padding(.leading, 14 * prefs.layoutScale)
        .padding(.trailing, 4)
        .padding(.vertical, 4)
        .frame(minHeight: 38 * prefs.layoutScale)
        .floatingGlassIsland(in: Capsule(style: .continuous))
    }

    private var agenda: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(dayFormatter.string(from: selection))
                .font(Theme.font(Theme.Size.dayHeader, prefs.layoutScale, weight: .semibold))
                .foregroundStyle(.secondary)

            let items = visibleItems
            if items.isEmpty {
                Text(hiddenPastCount > 0 ? "Heute ist nichts mehr offen." : "Nichts geplant.")
                    .font(Theme.font(Theme.Size.itemTitle, prefs.layoutScale))
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            }
            // Auch ohne Einträge: Die Gruppe „Aufgaben" steht mit ihrem „+" da, solange
            // Kalli Erinnerungen schreiben darf — sonst gäbe es an leeren Tagen keinen Weg.
            if !groups.isEmpty {
                // minHeight ist der Punkt: eine ScrollView hat keine eigene
                // Höhe und schrumpft im VStack sonst auf eine einzige Zeile,
                // egal wie viele Einträge drinstehen.
                ScrollView {
                    // Drei Arten, drei Gruppen. Ganztägiges, Termine mit
                    // Uhrzeit und Aufgaben beantworten verschiedene Fragen —
                    // in einer durchlaufenden Liste sehen sie gleich aus und
                    // man muss jede Zeile einzeln einordnen.
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(groups, id: \.kind) { group in
                            AgendaGroup(
                                title: group.kind.title,
                                items: group.items,
                                isCollapsed: group.kind.isCollapsible
                                    ? prefs.collapsedGroups.contains(group.kind) : nil,
                                onToggleCollapse: {
                                    withAnimation(.easeInOut(duration: 0.18)) { prefs.toggleCollapsed(group.kind) }
                                },
                                onAdd: group.kind == .tasks && canCreateReminders ? {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        addingReminder.toggle()
                                        // Wer etwas anlegt, will die Liste sehen.
                                        if addingReminder { prefs.collapsedGroups.remove(.tasks) }
                                    }
                                } : nil,
                                isAdding: group.kind == .tasks && addingReminder,
                                addField: group.kind == .tasks && addingReminder ? AnyView(
                                    QuickReminderField(
                                        initialDay: defaultReminderDay,
                                        calendar: calendar,
                                        scale: prefs.layoutScale,
                                        onSave: { draft in await store.createReminder(draft, calendar: calendar) },
                                        onDone: { withAnimation(.easeInOut(duration: 0.15)) { addingReminder = false } }
                                    )
                                ) : nil,
                                showProgress: prefs.showRunningProgress,
                                scale: prefs.layoutScale,
                                justCompleted: justCompleted,
                                oneThingID: oneThing.reminderID,
                                onToggle: { item in toggle(item) },
                                onMakeOneThing: { item in oneThing.set(reminderID: item.id, title: item.title) }
                            )
                        }
                        if hiddenPastCount > 0 {
                            Button {
                                prefs.showPastEvents = true
                            } label: {
                                Text(hiddenPastCount == 1
                                     ? "1 vergangener Termin ausgeblendet"
                                     : "\(hiddenPastCount) vergangene Termine ausgeblendet")
                                    .font(Theme.font(Theme.Size.hint, prefs.layoutScale))
                                    .foregroundStyle(.tertiary)
                            }
                            .buttonStyle(.plain)
                            .help("Klicken, um vergangene Termine wieder anzuzeigen")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 2)
                }
                .scrollIndicators(.automatic)
                .frame(minHeight: min(min(CGFloat(groups.count) * 24 + CGFloat(visibleRowCount) * 46
                                          + (addingReminder ? 150 : 0), 380)
                                      * prefs.layoutScale, listCap),
                       maxHeight: min(560 * prefs.layoutScale, listCap))
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { listHeight = $0 }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Was oben hervorgehoben wird: der laufende Termin hat Vorrang vor dem
    /// nächsten — was gerade passiert, ist dringender als was kommt.
    private var bannerItem: AgendaItem? {
        if let running = store.runningEvent { return running }
        guard let next = store.nextEvent, let start = next.start else { return nil }
        let lead = TimeInterval(prefs.upcomingLeadMinutes * 60)
        return start.timeIntervalSinceNow <= lead ? next : nil
    }

    private var visibleItems: [AgendaItem] {
        // Der Vergangenheitsfilter greift NUR am heutigen Tag. An einem anderen
        // Tag ist alles vergangen oder alles künftig — dort würde er die Liste
        // komplett leeren und sähe aus wie ein Fehler.
        let filterPast = prefs.hidePastEvents && calendar.isDateInToday(selection)
        return store.items(on: selection, calendar: calendar)
            // Gerade Abgehaktes ueberlebt den Filter fuer ein paar Sekunden.
            // Ohne das verschwindet die Zeile im selben Moment wie der Klick,
            // und der Nutzer sieht nicht, ob er getroffen hat oder danebenlag.
            .filter { prefs.showCompletedReminders || !$0.isCompleted
                      || justCompleted.contains($0.id) }
            .filter { !filterPast || !$0.isOver() }
    }

    /// Wie viele Einträge der Vergangenheitsfilter gerade verbirgt.
    /// Eine versteckte Zeile ohne Hinweis sieht aus wie ein fehlender Termin.
    private var hiddenPastCount: Int {
        guard prefs.hidePastEvents, calendar.isDateInToday(selection) else { return 0 }
        return store.items(on: selection, calendar: calendar)
            .filter { prefs.showCompletedReminders || !$0.isCompleted }
            .filter { $0.isOver() }
            .count
    }

    /// Reihenfolge der Gruppen: erst was den ganzen Tag gilt (der Rahmen),
    /// dann was zu einer Uhrzeit passiert, zuletzt was ohne feste Zeit zu tun ist.
    private var groups: [(kind: AgendaGroupKind, items: [AgendaItem])] {
        let all = visibleItems
        let allDay = all.filter { $0.isAllDay && !$0.isReminder }
        let timed = all.filter { !$0.isAllDay && !$0.isReminder }
        let tasks = all.filter(\.isReminder)
        let byKind: [AgendaGroupKind: [AgendaItem]] = [.allDay: allDay, .timed: timed, .tasks: tasks]
        return prefs.agendaOrder.map { ($0, byKind[$0] ?? []) }
            .filter { !$0.1.isEmpty || ($0.0 == .tasks && canCreateReminders) }
    }

    /// Zeilen, die gerade sichtbar sind (zugeklappte Gruppen zählen nicht) — für die Mindesthöhe.
    private var visibleRowCount: Int {
        groups.filter { !($0.kind.isCollapsible && prefs.collapsedGroups.contains($0.kind)) }
            .reduce(0) { $0 + $1.items.count }
    }

    private var canCreateReminders: Bool { store.reminderPermission == .granted }

    /// Vorbelegt mit dem gewählten Tag — liegt der in der Vergangenheit, heute.
    private var defaultReminderDay: Date {
        let today = calendar.startOfDay(for: Date())
        return max(calendar.startOfDay(for: selection), today)
    }

    private var accessHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Kein Zugriff auf Kalender")
                .font(Theme.font(Theme.Size.itemTitle, prefs.layoutScale, weight: .semibold))
            Text("→ ZU TUN: Systemeinstellungen → Datenschutz & Sicherheit → "
                 + "Kalender bzw. Erinnerungen → Kalli aktivieren.")
                .font(Theme.font(Theme.Size.itemTime, prefs.layoutScale))
                .foregroundStyle(.secondary)
            Button("Systemeinstellungen öffnen") {
                let url = "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
                if let u = URL(string: url) { NSWorkspace.shared.open(u) }
            }
            .font(Theme.font(Theme.Size.itemTime, prefs.layoutScale))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    /// Hakt ab oder nimmt zurueck — mit sichtbarem Nachleuchten.
    private func toggle(_ item: AgendaItem) {
        let wasCompleted = item.isCompleted
        Task {
            if let error = await store.setCompleted(!wasCompleted, for: item) {
                toggleError = error
                return
            }
            toggleError = nil

            if wasCompleted {
                // Haekchen zurueckgenommen: Zeile bleibt ohnehin stehen.
                withAnimation { _ = justCompleted.remove(item.id) }
                return
            }

            // Abgehakt: kurz sichtbar lassen, dann ausblenden.
            withAnimation(.easeOut(duration: 0.2)) {
                _ = justCompleted.insert(item.id)
            }
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.easeInOut(duration: 0.35)) {
                _ = justCompleted.remove(item.id)
            }
        }
    }

    private func step(_ months: Int) {
        guard let next = calendar.date(byAdding: .month, value: months, to: visibleMonth)
        else { return }
        visibleMonth = next
    }
}

/// Schlanker Fortschrittsbalken mit runden Enden.
///
/// Statt `ProgressView(.linear)`: Der Systembalken bringt eigene Höhe, eigene
/// Einfassung und eine eckige Spur mit — drei Dinge, die sich nicht anpassen
/// lassen und neben runden Karten fremd wirken.
struct ProgressBar: View {
    let value: Double
    let color: Color
    let height: CGFloat

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.10))
                Capsule()
                    .fill(
                        LinearGradient(colors: [color, color.opacity(0.75)],
                                       startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: max(height, geo.size.width * min(max(value, 0), 1)))
            }
        }
        .frame(height: height)
    }
}

/// Auffälliger Hinweis oben im Popover: was gerade läuft oder gleich beginnt.
private struct UpcomingBanner: View {
    let item: AgendaItem
    let showProgress: Bool
    var scale: Double = 1.0

    var body: some View {
        let progress = item.progress()
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Circle()
                    .fill(Color(red: item.color.r, green: item.color.g, blue: item.color.b))
                    .frame(width: 8, height: 8)
                Text(item.title)
                    .font(Theme.font(Theme.Size.bannerTitle, scale, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(progress != nil
                     ? (item.remainingLabel() ?? "läuft")
                     : (item.startsInLabel() ?? ""))
                    .font(Theme.font(Theme.Size.itemTime, scale, weight: .medium))
                    .foregroundStyle(progress != nil ? .primary : .secondary)
            }
            if showProgress, let progress {
                ProgressBar(value: progress,
                            color: Color(red: item.color.r, green: item.color.g,
                                         blue: item.color.b),
                            height: 5)
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Theme.cardRadius)
                .fill(Theme.accent.opacity(0.10))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.cardRadius)
                        .strokeBorder(Theme.accent.opacity(0.22), lineWidth: 0.8)
                }
        }
    }
}

// MARK: - Öffnen und Höhe (2026-11-18)

extension PopoverView {
    /// Läuft bei jedem Öffnen. Neuer Tag seit dem letzten Öffnen → zurück auf heute; am selben
    /// Tag bleibt der angeklickte Tag stehen (Michael, 2026-11-18).
    func popoverOpened() {
        let now = Date()
        if !calendar.isDate(lastOpened, inSameDayAs: now) {
            visibleMonth = now
            selection = now
        }
        lastOpened = now
        // Das Popover geht auf dem Bildschirm auf, in dessen Menüleiste geklickt wurde.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        screenHeight = screen?.visibleFrame.height ?? .infinity
    }

    /// Höchste Höhe der Tagesliste, bei der das ganze Popover noch auf den Bildschirm passt.
    /// Der Rest des Popovers (Raster, Kopf, Fuß) hängt nicht von der Liste ab, deshalb
    /// schwingt die Rechnung nicht.
    var listCap: CGFloat {
        guard screenHeight.isFinite, totalHeight > 0 else { return .infinity }
        let rest = totalHeight - listHeight
        return max(120 * prefs.layoutScale, screenHeight - rest - 16)
    }
}

// Fußleiste als eigene Erweiterung: hält den Typ-Rumpf unter der SwiftLint-Sperrklinke (350 Zeilen).
extension PopoverView {
    private var footer: some View {
        // Runde 2 der Glas-Sprache: Die ganze Fußleiste ist eine Glas-Insel; alle Knöpfe darin ohne
        // eigenes Glas, mit gleitendem Hover-Schatten (vorher Glasgruppe + einzelne Glas-Kapseln).
        let size = 26 * prefs.layoutScale
        return HStack(spacing: 1) {
            HStack(spacing: 1) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { showingSettings.toggle() }
                } label: {
                    Image(systemName: showingSettings ? "chevron.left" : "gearshape")
                        .frame(width: size, height: size).contentShape(Capsule())
                }
                .buttonStyle(.glassPress)
                .glassGhostItem()
                .help(showingSettings ? "Zurück zum Kalender" : "Einstellungen")
                .accessibilityLabel(Text(showingSettings ? "Zurück zum Kalender" : "Einstellungen"))

                // Hell/Dunkel mit einem Klick: System → Hell → Dunkel. Das Symbol zeigt
                // den aktuellen Stand (Michael, 2026-09-29).
                Button {
                    prefs.appearanceMode = prefs.appearanceMode.next
                    prefs.appearanceMode.apply()
                } label: {
                    Image(systemName: prefs.appearanceMode.symbol)
                        .contentTransition(.symbolEffect(.replace))
                        .frame(width: size, height: size).contentShape(Capsule())
                }
                .buttonStyle(.glassPress)
                .glassGhostItem()
                .help("Erscheinungsbild: \(prefs.appearanceMode.title) — klicken zum Wechseln")
                .accessibilityLabel(Text("Erscheinungsbild: \(prefs.appearanceMode.title)"))
            }
            .foregroundStyle(FamilyTheme.textPrimary)

            // Ohne diesen Knopf gibt es keinen Weg, eine Prüfung willentlich
            // auszulösen — die automatische Suche ist ab Werk aus, weil sie
            // eine Netzverbindung ist, die niemand erteilt hat.
            //
            // **Mit Text, nicht nur Symbol.** In 0.4.0 stand hier allein ein
            // Kreispfeil, und Michael sagte zu Recht: „Das Reload-Icon allein
            // ist nicht zu verstehen." Ein Kreispfeil in einer Kalender-App
            // liest sich wie „Termine neu laden", nicht wie „Updates". Das
            // Zahnrad daneben darf symbolfrei bleiben, weil es überall
            // dasselbe bedeutet — dieses hier nicht.
            Button {
                updater.checkForUpdates()
            } label: {
                // Hat eine automatische Prüfung etwas gefunden, sagt der Knopf
                // es — die zweite Stelle neben der Mitteilung, falls die aus ist.
                Label(updater.bereitesUpdate.map { "Update \($0)" } ?? "Updates",
                      systemImage: updater.bereitesUpdate == nil ? "arrow.down.circle" : "arrow.down.circle.fill")
                    .font(Theme.font(Theme.Size.itemTime, prefs.layoutScale))
                    .padding(.horizontal, size * 0.42).frame(height: size).contentShape(Capsule())
            }
            .buttonStyle(.glassPress)
            .glassGhostItem(updater.canCheck)
            .disabled(!updater.canCheck)
            .help(updater.bereitesUpdate == nil ? "Nach Updates suchen" : "Update ansehen und installieren")

            Spacer()
            Button { NSApplication.shared.terminate(nil) } label: {
                Text("Beenden")
                    .font(Theme.font(Theme.Size.itemTime, prefs.layoutScale))
                    .padding(.horizontal, size * 0.42).frame(height: size).contentShape(Capsule())
            }
            .buttonStyle(.glassPress)
            .glassGhostItem()
        }
        .foregroundStyle(FamilyTheme.textPrimary)
        .frame(height: size + 4)
        .glassGhostHost()
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .floatingGlassIsland(in: Capsule(style: .continuous))
    }
}
