import SwiftUI

struct PopoverView: View {

    @Environment(Preferences.self) private var prefs
    @Environment(CalendarStore.self) private var store
    @Environment(MenuBarLabel.self) private var label
    @Environment(\.openSettings) private var openSettings

    @State private var visibleMonth = Date()
    @State private var selection = Date()

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

            if case .denied = store.access {
                accessHint
            } else {
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
        .frame(width: prefs.showWeekNumbers ? 288 : 262)
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
            Text(monthFormatter.string(from: visibleMonth).capitalized)
                .font(.headline)
            Spacer()
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
        .buttonStyle(.accessoryBar)
    }

    private var agenda: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(dayFormatter.string(from: selection))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            let items = visibleItems
            if items.isEmpty {
                Text("Nichts geplant.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(items) { AgendaRow(item: $0) }
                    }
                }
                .frame(maxHeight: 190)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Termine zuerst, Erinnerungen darunter — sie haben oft keine Uhrzeit und
    /// würden die Zeitachse sonst durchbrechen.
    private var visibleItems: [AgendaItem] {
        let all = store.items(on: selection, calendar: calendar)
            .filter { prefs.showCompletedReminders || !$0.isCompleted }
        return all.filter { !$0.isReminder } + all.filter(\.isReminder)
    }

    private var accessHint: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Kein Zugriff auf Kalender").font(.callout.weight(.semibold))
            Text("→ ZU TUN: Systemeinstellungen → Datenschutz & Sicherheit → "
                 + "Kalender bzw. Erinnerungen → MacCal aktivieren.")
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
                openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Einstellungen")
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

private struct AgendaRow: View {
    let item: AgendaItem

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Group {
                if item.isReminder {
                    Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 9))
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
                    .font(.caption)
                    .strikethrough(item.isCompleted)
                    .foregroundStyle(item.isCompleted ? .secondary : .primary)
                let time = item.timeLabel(using: timeFormatter)
                if !time.isEmpty {
                    Text(time).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
