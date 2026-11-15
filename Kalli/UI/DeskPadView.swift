import SwiftUI

/// Das Tagesblatt auf dem Schreibtisch (0.14.0, Michael 2026-11-15: „wie Daypad, mit Terminen
/// und Aufgaben“). Zeigt einen Tag in denselben Gruppen wie die Tagesliste im Popover; die
/// Aufgaben lassen sich hier abhaken. Blättern mit ‹ Heute ›, ohne Animation (erste Stufe).
///
/// Lädt seinen Tag selbst über `CalendarStore.dayItems` und stört damit den Monat des
/// Popovers nicht. Neu geladen wird bei Tagwechsel und bei jedem `store.revision`.
struct DeskPadView: View {
    @Environment(Preferences.self) private var prefs
    @Environment(CalendarStore.self) private var store

    @State private var day = Calendar.current.startOfDay(for: Date())
    /// `false` = das Blatt zeigt immer den aktuellen Tag und springt um Mitternacht mit.
    @State private var pinned = false
    @State private var items: [AgendaItem] = []
    @State private var justCompleted: Set<String> = []
    @State private var toggleError: String?

    private let calendar = Calendar.current

    private let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "EEEE"
        return f
    }()

    private let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    private var scale: Double { prefs.layoutScale }
    private var isToday: Bool { calendar.isDateInToday(day) }

    private var sections: [DeskPad.Section] {
        DeskPad.sections(from: items, order: prefs.agendaOrder,
                         showCompleted: prefs.showCompletedReminders, keeping: justCompleted)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12 * scale) {
            header
            content
        }
        .padding(18 * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .movesWindow()
        .contextMenu {
            Button("Tagesblatt ausblenden", systemImage: "eye.slash") { prefs.deskPadEnabled = false }
        }
        .glassSurface(in: RoundedRectangle(cornerRadius: 24 * scale))
        .task(id: "\(day.timeIntervalSince1970)-\(store.revision)") {
            if !pinned {
                let today = calendar.startOfDay(for: Date())
                if today != day { day = today; return }  // neue Task-ID lädt den neuen Tag
            }
            items = await store.dayItems(day, calendar: calendar)
        }
    }

    // MARK: - Kopf

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 0) {
                Text(weekdayFormatter.string(from: day).uppercased())
                    .font(Theme.font(Theme.Size.groupTitle + 1, scale, weight: .semibold))
                    .tracking(1.0)
                    .foregroundStyle(isToday ? Theme.accent : .secondary)
                Text(verbatim: "\(calendar.component(.day, from: day))")
                    .font(Theme.font(46, scale, weight: .bold))
                    .foregroundStyle(isToday ? Theme.accent : .primary)
                    .contentTransition(.numericText())
                Text(monthFormatter.string(from: day))
                    .font(Theme.font(Theme.Size.dayHeader, scale, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            navigation
        }
    }

    private var navigation: some View {
        let size = 26 * scale
        return GlassGroup(height: size + 4) {
            Button { move(-1) } label: {
                Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                    .frame(width: size, height: size).contentShape(Capsule())
            }
            .buttonStyle(.glassPress)
            .glassGhostItem()
            .help("Vorheriger Tag")
            .accessibilityLabel(Text("Vorheriger Tag"))
            Button {
                pinned = false
                day = calendar.startOfDay(for: Date())
            } label: {
                Text("Heute").font(Theme.font(Theme.Size.itemTime, scale, weight: .medium))
                    .padding(.horizontal, size * 0.35).frame(height: size).contentShape(Capsule())
            }
            .buttonStyle(.glassPress)
            .glassGhostItem()
            .help("Zurück zum heutigen Tag")
            Button { move(1) } label: {
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                    .frame(width: size, height: size).contentShape(Capsule())
            }
            .buttonStyle(.glassPress)
            .glassGhostItem()
            .help("Nächster Tag")
            .accessibilityLabel(Text("Nächster Tag"))
        }
        .foregroundStyle(FamilyTheme.textPrimary)
    }

    // MARK: - Inhalt

    @ViewBuilder
    private var content: some View {
        if case .denied = store.access {
            Text("Kalli darf Kalender und Erinnerungen nicht lesen. Freigabe im Popover unter „Berechtigungen“.")
                .font(Theme.font(Theme.Size.itemTitle, scale))
                .foregroundStyle(.secondary)
        } else if sections.isEmpty {
            Text("Nichts geplant.")
                .font(Theme.font(Theme.Size.itemTitle, scale))
                .foregroundStyle(.tertiary)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 10 * scale) {
                    ForEach(sections) { section in
                        AgendaGroup(title: section.kind.title,
                                    items: section.items,
                                    showProgress: prefs.showRunningProgress,
                                    scale: scale,
                                    justCompleted: justCompleted,
                                    onToggle: { toggle($0) })
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.automatic)
        }
        if let toggleError {
            Text(toggleError)
                .font(Theme.font(Theme.Size.hint, scale))
                .foregroundStyle(.red)
        }
    }

    // MARK: - Aktionen

    private func move(_ days: Int) {
        day = DeskPad.shifted(day, by: days, calendar: calendar)
        pinned = !calendar.isDateInToday(day)
    }

    /// Wie im Popover: abhaken, kurz sichtbar lassen, dann ausblenden. Geschrieben wird
    /// über denselben `setCompleted`, mit derselben Nachprüfung.
    private func toggle(_ item: AgendaItem) {
        let wasCompleted = item.isCompleted
        Task {
            if let error = await store.setCompleted(!wasCompleted, for: item) {
                toggleError = error
                return
            }
            toggleError = nil
            items = await store.dayItems(day, calendar: calendar)
            guard !wasCompleted else {
                withAnimation { _ = justCompleted.remove(item.id) }
                return
            }
            withAnimation(.easeOut(duration: 0.2)) { _ = justCompleted.insert(item.id) }
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.easeInOut(duration: 0.35)) { _ = justCompleted.remove(item.id) }
        }
    }
}
