import SwiftUI

struct PopoverView: View {

    @Environment(Preferences.self) private var prefs
    @Environment(CalendarStore.self) private var store
    @Environment(MenuBarLabel.self) private var label

    @State private var visibleMonth = Date()
    @State private var selection = Date()
    @State private var showingSettings = false
    @State private var toggleError: String?

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
            } else if case .denied = store.access {
                accessHint
            } else {
                if prefs.showUpcomingBanner, let banner = bannerItem {
                    UpcomingBanner(item: banner, showProgress: prefs.showRunningProgress)
                }
                MonthGrid(
                    month: visibleMonth,
                    selection: $selection,
                    calendar: calendar,
                    showWeekNumbers: prefs.showWeekNumbers,
                    hasItems: { store.hasItems(on: $0, calendar: calendar) }
                )
                Divider()
                agenda
            }

            footer
        }
        .padding(12)
        .frame(width: prefs.showWeekNumbers ? 396 : 360)
        // Liquid Glass gehört genau hierhin: ein Popover ist eine schwebende
        // Fläche. Fensterkörper bekommen das ausdrücklich NICHT — siehe
        // GlassBackground.swift.
        .glassSurface(in: RoundedRectangle(cornerRadius: 12))
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
                .font(.headline)
            Spacer()
            if !showingSettings {
                Button { step(-1) } label: { Image(systemName: "chevron.left") }
                    .help("Vorheriger Monat")
                Button {
                    visibleMonth = Date()
                    selection = Date()
                } label: {
                    Text("Heute").font(.caption)
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
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            let items = visibleItems
            if items.isEmpty {
                Text(hiddenPastCount > 0 ? "Heute ist nichts mehr offen." : "Nichts geplant.")
                    .font(.caption)
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
                                onToggle: { item in
                                    Task {
                                        if let error = await store.setCompleted(
                                            !item.isCompleted, for: item) {
                                            toggleError = error
                                        } else {
                                            toggleError = nil
                                        }
                                    }
                                }
                            )
                        }
                        if let toggleError {
                            Label(toggleError, systemImage: "exclamationmark.triangle")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                        if hiddenPastCount > 0 {
                            Button {
                                prefs.hidePastEvents = false
                            } label: {
                                Text(hiddenPastCount == 1
                                     ? "1 vergangener Termin ausgeblendet"
                                     : "\(hiddenPastCount) vergangene Termine ausgeblendet")
                                    .font(.caption2)
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
                .frame(minHeight: min(CGFloat(groups.count) * 24 + CGFloat(items.count) * 46, 380),
                       maxHeight: 560)
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
            .filter { prefs.showCompletedReminders || !$0.isCompleted }
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
            Text("Kein Zugriff auf Kalender").font(.callout.weight(.semibold))
            Text("→ ZU TUN: Systemeinstellungen → Datenschutz & Sicherheit → "
                 + "Kalender bzw. Erinnerungen → Kalli aktivieren.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Systemeinstellungen öffnen") {
                let url = "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
                if let u = URL(string: url) { NSWorkspace.shared.open(u) }
            }
            .font(.caption)
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
            Spacer()
            Button("Beenden") { NSApplication.shared.terminate(nil) }
                .font(.caption)
        }
        .buttonStyle(.accessoryBar)
    }

    private func step(_ months: Int) {
        guard let next = calendar.date(byAdding: .month, value: months, to: visibleMonth)
        else { return }
        visibleMonth = next
    }
}

/// Eine Gruppe mit Überschrift. Trennlinien nur innerhalb der Gruppe — die
/// Gruppen selbst trennt der Abstand plus die Überschrift.
private struct AgendaGroup: View {
    let title: String
    let items: [AgendaItem]
    let showProgress: Bool
    var onToggle: ((AgendaItem) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 3)

            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 {
                    Divider().opacity(0.35).padding(.leading, 17)
                }
                AgendaRow(item: item, showProgress: showProgress,
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

    var body: some View {
        let progress = item.progress()
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Circle()
                    .fill(Color(red: item.color.r, green: item.color.g, blue: item.color.b))
                    .frame(width: 8, height: 8)
                Text(item.title)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(progress != nil
                     ? (item.remainingLabel() ?? "läuft")
                     : (item.startsInLabel() ?? ""))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(progress != nil ? .primary : .secondary)
            }
            if showProgress, let progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(Color(red: item.color.r, green: item.color.g, blue: item.color.b))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
    }
}

private struct AgendaRow: View {
    let item: AgendaItem
    let showProgress: Bool
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
                            .font(.system(size: 11))
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
                    .font(.callout)
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                let time = item.timeLabel(using: timeFormatter)
                if !time.isEmpty {
                    HStack(spacing: 6) {
                        Text(time).font(.caption).foregroundStyle(.secondary)
                        if let remaining = item.remainingLabel() {
                            Text(remaining)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.tint)
                        }
                    }
                }
                if showProgress, let progress = item.progress() {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(Color(red: item.color.r, green: item.color.g, blue: item.color.b))
                        .frame(height: 2)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
