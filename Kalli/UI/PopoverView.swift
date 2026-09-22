import SwiftUI

struct PopoverView: View {

    @Environment(Preferences.self) private var prefs
    @Environment(CalendarStore.self) private var store
    @Environment(MenuBarLabel.self) private var label
    @Environment(Updater.self) private var updater

    @State private var visibleMonth = Date()
    @State private var selection = Date()
    @State private var showingSettings = false
    @State private var toggleError: String?
    /// Gerade abgehakte Aufgaben. Sie bleiben kurz stehen, damit das Abhaken
    /// sichtbar wird, bevor der Filter sie entfernt.
    @State private var justCompleted: Set<String> = []

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
        VStack(spacing: 10) {
            header
            Divider()

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
                        .foregroundStyle(.orange)
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
                    hasItems: { store.hasItems(on: $0, calendar: calendar) }
                )
                Divider()
                agenda
            }

            // Die Fehlermeldung stand bis 2026-09-22 INNERHALB der ScrollView,
            // hinter der Terminliste. Bei voller Agenda lag sie unter der Falz
            // und war nur nach Scrollen zu sehen — eine Meldung, die man
            // suchen muss, ist keine. Sie gehoert an einen festen Platz.
            if let toggleError {
                Label(toggleError, systemImage: "exclamationmark.triangle")
                    .font(Theme.font(Theme.Size.hint, prefs.layoutScale))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            footer
        }
        .padding(12)
        .frame(width: (prefs.showWeekNumbers ? 396 : 360) * prefs.layoutScale)

        // Liquid Glass gehört genau hierhin: ein Popover ist eine schwebende
        // Fläche. Fensterkörper bekommen das ausdrücklich NICHT — siehe
        // GlassBackground.swift.
        .glassSurface(in: RoundedRectangle(cornerRadius: 14))
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
                .font(Theme.font(Theme.Size.monthTitle, prefs.layoutScale, weight: .semibold))
                .contentTransition(.numericText())
            Spacer()
            if !showingSettings {
                Button { step(-1) } label: { Image(systemName: "chevron.left") }
                    .help("Vorheriger Monat")
                Button {
                    visibleMonth = Date()
                    selection = Date()
                } label: {
                    Text("Heute").font(Theme.font(Theme.Size.itemTime, prefs.layoutScale))
                }
                .help("Zurück zum heutigen Tag")
                Button { step(1) } label: { Image(systemName: "chevron.right") }
                    .help("Nächster Monat")
            }
        }
        .buttonStyle(.accessoryBar)
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
            } else {
                // minHeight ist der Punkt: eine ScrollView hat keine eigene
                // Höhe und schrumpft im VStack sonst auf eine einzige Zeile,
                // egal wie viele Einträge drinstehen.
                ScrollView {
                    // Drei Arten, drei Gruppen. Ganztägiges, Termine mit
                    // Uhrzeit und Aufgaben beantworten verschiedene Fragen —
                    // in einer durchlaufenden Liste sehen sie gleich aus und
                    // man muss jede Zeile einzeln einordnen.
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(groups, id: \.title) { group in
                            AgendaGroup(
                                title: group.title,
                                items: group.items,
                                showProgress: prefs.showRunningProgress,
                                scale: prefs.layoutScale,
                                justCompleted: justCompleted,
                                onToggle: { item in toggle(item) }
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
                .frame(minHeight: min(CGFloat(groups.count) * 24 + CGFloat(items.count) * 46, 380)
                                  * prefs.layoutScale,
                       maxHeight: 560 * prefs.layoutScale)
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
    private var groups: [(title: String, items: [AgendaItem])] {
        let all = visibleItems
        let allDay = all.filter { $0.isAllDay && !$0.isReminder }
        let timed = all.filter { !$0.isAllDay && !$0.isReminder }
        let tasks = all.filter(\.isReminder)
        return [
            ("Ganztägig", allDay),
            ("Termine", timed),
            ("Aufgaben", tasks),
        ].filter { !$0.1.isEmpty }
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

    private var footer: some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { showingSettings.toggle() }
            } label: {
                Image(systemName: showingSettings ? "chevron.left" : "gearshape")
            }
            .help(showingSettings ? "Zurück zum Kalender" : "Einstellungen")

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
                Label("Updates", systemImage: "arrow.down.circle")
                    .font(Theme.font(Theme.Size.itemTime, prefs.layoutScale))
            }
            .disabled(!updater.canCheck)
            .help("Nach Updates suchen")

            Spacer()
            Button("Beenden") { NSApplication.shared.terminate(nil) }
                .font(Theme.font(Theme.Size.itemTime, prefs.layoutScale))
        }
        .buttonStyle(.accessoryBar)
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
private struct ProgressBar: View {
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

/// Eine Gruppe mit Überschrift. Trennlinien nur innerhalb der Gruppe — die
/// Gruppen selbst trennt der Abstand plus die Überschrift.
private struct AgendaGroup: View {
    let title: String
    let items: [AgendaItem]
    let showProgress: Bool
    var scale: Double = 1.0
    var justCompleted: Set<String> = []
    var onToggle: ((AgendaItem) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(Theme.font(Theme.Size.groupTitle, scale, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 5)

            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Divider().opacity(0.22).padding(.leading, 18)
                }
                AgendaRow(item: item, showProgress: showProgress, scale: scale,
                          isFading: justCompleted.contains(item.id),
                          onToggle: { onToggle?(item) })
                    .padding(.vertical, 5)
            }
        }
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

private struct AgendaRow: View {
    let item: AgendaItem
    let showProgress: Bool
    var scale: Double = 1.0
    var isFading: Bool = false
    var onToggle: (() -> Void)? = nil

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            // Drei Arten, drei Formen — nicht dieselbe Form in drei Farben.
            // Die Form trägt die Bedeutung auch dann, wenn zwei Kalender
            // zufällig ähnlich eingefärbt sind.
            Group {
                if item.isReminder {
                    // Der Marker ist hier zugleich der Schalter. Ein separater
                    // Knopf daneben waere eine zweite Stelle fuer dieselbe
                    // Information -- das Haekchen IST die Handlung.
                    Button {
                        onToggle?()
                    } label: {
                        Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 12 * scale))
                            .symbolEffect(.bounce, value: item.isCompleted)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(item.isCompleted ? "Häkchen zurücknehmen" : "Als erledigt markieren")
                } else if item.isAllDay {
                    // Balken = gilt über die ganze Breite des Tages.
                    RoundedRectangle(cornerRadius: 1.5)
                        .frame(width: 9, height: 4)
                } else {
                    Circle().frame(width: 7, height: 7)
                }
            }
            .foregroundStyle(Color(
                red: item.color.r, green: item.color.g, blue: item.color.b
            ))
            .frame(width: 10)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.title)
                    .font(Theme.font(Theme.Size.itemTitle, scale))
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                let time = item.timeLabel(using: timeFormatter)
                if !time.isEmpty {
                    HStack(spacing: 6) {
                        Text(time)
                            .font(Theme.font(Theme.Size.itemTime, scale))
                            .foregroundStyle(.secondary)
                        if let remaining = item.remainingLabel() {
                            Text(remaining)
                                .font(Theme.font(Theme.Size.hint, scale, weight: .medium))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }
                if showProgress, let progress = item.progress() {
                    ProgressBar(value: progress,
                                color: Color(red: item.color.r, green: item.color.g,
                                             blue: item.color.b),
                                height: 3)
                }
            }
            Spacer(minLength: 0)

            // Nur solange die Zeile nachleuchtet: ein Weg zurueck. Danach
            // bleibt der Kreis selbst der Schalter.
            if isFading {
                Button("Rückgängig") { onToggle?() }
                    .font(Theme.font(Theme.Size.hint, scale, weight: .medium))
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
            }
        }
        .opacity(isFading ? 0.55 : 1)
        .background {
            if isFading {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Theme.accent.opacity(0.10))
                    .padding(.horizontal, -4)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .leading)))
    }
}
