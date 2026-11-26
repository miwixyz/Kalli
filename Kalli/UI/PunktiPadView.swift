import SwiftUI

/// Das Tagesblatt im Punkti-Look (Michael 2026-11-26: „Das Kalenderblatt bitte auch im moderneren
/// Punktidesign“): dunkles Glas mit Farbflecken, Glasscheibe mit Tagesring und LED-Tageszahl, daneben
/// der Monat, darunter ‹ HEUTE › und alle Einträge des Tages mit LED-Uhrzeit. Aufgaben lassen sich
/// abhaken wie im Glas-Blatt; Laden und Abhaken laufen über dieselben Wege (`dayItems`, `setCompleted`).
struct PunktiPadView: View {
    @Environment(Preferences.self) private var prefs
    @Environment(CalendarStore.self) private var store
    @Environment(DeskPadScale.self) private var fit

    @State private var day = Calendar.current.startOfDay(for: Date())
    /// `false` = das Blatt zeigt immer den aktuellen Tag und springt um Mitternacht mit.
    @State private var pinned = false
    @State private var items: [AgendaItem] = []
    @State private var justCompleted: Set<String> = []
    @State private var toggleError: String?

    private let calendar = Calendar.current
    private let color = Color.white
    private var scale: Double { fit.value }

    private var shown: [AgendaItem] {
        DeskPad.sections(from: items, order: prefs.agendaOrder,
                         showCompleted: prefs.showCompletedReminders, keeping: justCompleted)
            .flatMap(\.items)
    }

    private var openLabel: String {
        let open = items.filter { !$0.isCompleted }.count
        return open == 0 ? "FREI" : "\(open) \(open == 1 ? "EINTRAG" : "EINTRÄGE")"
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 28 * scale, style: .continuous)
        VStack(spacing: 12 * scale) {
            HStack(spacing: 12 * scale) {
                // Ohne Monat in der Fußzeile: Der steht daneben groß, und die Zeile bleibt lesbar kurz.
                PunktiDayDisc(date: day, footer: openLabel, color: color)
                    .frame(width: 148 * scale, height: 148 * scale)
                PunktiMonthGrid(date: day, color: color)
                    .frame(maxWidth: .infinity)
                    .frame(height: 160 * scale)
            }
            navigation
            content
        }
        .padding(16 * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(PunktiGlassBackground())
        .clipShape(shape)
        .overlay(shape.strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.05), .white.opacity(0.15)],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
        .movesWindow()
        .contextMenu {
            Button("Tagesblatt ausblenden", systemImage: "eye.slash") { prefs.deskPadEnabled = false }
        }
        .environment(\.colorScheme, .dark)
        .task(id: "\(day.timeIntervalSince1970)-\(store.revision)") {
            if !pinned {
                let today = calendar.startOfDay(for: Date())
                if today != day { day = today; return }
            }
            items = await store.dayItems(day, calendar: calendar)
        }
    }

    // MARK: - Blättern

    private var navigation: some View {
        HStack(spacing: 6 * scale) {
            navButton(systemImage: "chevron.left", help: "Vorheriger Tag") { move(-1) }
            Button {
                pinned = false
                day = calendar.startOfDay(for: Date())
            } label: {
                Text(verbatim: "HEUTE")
                    .font(.system(size: 11 * scale, weight: .semibold, design: .monospaced))
                    .tracking(1.5 * scale)
                    .padding(.horizontal, 12 * scale)
                    .frame(height: 26 * scale)
                    .background(Capsule().fill(color.opacity(calendar.isDateInToday(day) ? 0.18 : 0.08)))
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .help("Zurück zum heutigen Tag")
            navButton(systemImage: "chevron.right", help: "Nächster Tag") { move(1) }
        }
        .foregroundStyle(color.opacity(0.85))
    }

    private func navButton(systemImage: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 11 * scale, weight: .semibold))
                .frame(width: 26 * scale, height: 26 * scale)
                .background(Circle().fill(color.opacity(0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(Text(help))
    }

    // MARK: - Einträge

    @ViewBuilder
    private var content: some View {
        if case .denied = store.access {
            message(["KALENDER-ZUGRIFF", "IM POPOVER ERLAUBEN"])
        } else if shown.isEmpty {
            message(["NICHTS GEPLANT"])
        } else {
            TimelineView(.everyMinute) { context in
                ScrollViewReader { reader in
                    ScrollView {
                        VStack(spacing: 8 * scale) {
                            ForEach(shown) { item in
                                PunktiDayRow(item: item, now: context.date, color: color,
                                             onToggle: { toggle($0) }, unit: 50 * scale)
                                    .id(item.id)
                            }
                        }
                    }
                    // `.hidden` lässt den Balken stehen, wenn „Rollbalken immer einblenden“ gilt (gemessen 2026-11-26).
                    .scrollIndicators(.never)
                    // Heute oben das Anstehende zeigen, nicht die Termine vom Vormittag.
                    .onAppear { scrollToCurrent(reader, now: context.date) }
                    .onChange(of: shown.map(\.id)) { scrollToCurrent(reader, now: context.date) }
                }
            }
        }
        if let toggleError {
            Text(toggleError)
                .font(.system(size: 10 * scale))
                .foregroundStyle(.red)
        }
    }

    private func message(_ lines: [String]) -> some View {
        VStack(spacing: 6 * scale) {
            ForEach(lines, id: \.self) { line in
                Text(verbatim: line)
                    .font(.system(size: 12 * scale, weight: .medium, design: .monospaced))
                    .tracking(1.5 * scale)
                    .foregroundStyle(color.opacity(line == lines[0] ? 0.85 : 0.6))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Erster Eintrag, der nicht schon vorbei ist, an den oberen Rand.
    private func scrollToCurrent(_ reader: ScrollViewProxy, now: Date) {
        guard calendar.isDate(day, inSameDayAs: now),
              let target = shown.first(where: { !$0.isOver(at: now) }) else { return }
        reader.scrollTo(target.id, anchor: .top)
    }

    // MARK: - Aktionen

    private func move(_ days: Int) {
        day = DeskPad.shifted(day, by: days, calendar: calendar)
        pinned = !calendar.isDateInToday(day)
    }

    /// Wie im Glas-Blatt: abhaken, kurz sichtbar lassen, dann ausblenden.
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
