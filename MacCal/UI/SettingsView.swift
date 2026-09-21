import SwiftUI

/// Einstellungen **im Popover**, nicht in einem eigenen Fenster.
///
/// Zwei Versuche vorher, beide falsch: Eine `Settings`-Scene ging aus einer
/// `LSUIElement`-App gar nicht auf — der Knopf tat sichtbar nichts, und damit
/// waren Kalenderauswahl und alle Schalter unerreichbar, obwohl längst gebaut.
/// Ein selbst gehaltenes `NSWindow` öffnete sich zwar, aber hinter dem Popover
/// und als Fremdkörper neben einer Menüleisten-App.
///
/// Eine Menüleisten-App hat einen Ort: das Popover. Alles andere reißt den
/// Nutzer aus dem Zusammenhang, in dem er gerade steht.
struct SettingsView: View {

    enum Tab: String, CaseIterable, Identifiable {
        case sources = "Kalender"
        case menuBar = "Menüleiste"
        case popover = "Ansicht"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .sources

    var body: some View {
        VStack(spacing: 10) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    switch tab {
                    case .sources: SourcesSection()
                    case .menuBar: MenuBarSection()
                    case .popover: PopoverSection()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 2)
            }
            .frame(height: 330)
        }
    }
}

// MARK: - Kalender & Erinnerungslisten

private struct SourcesSection: View {
    @Environment(Preferences.self) private var prefs
    @Environment(CalendarStore.self) private var store

    var body: some View {
        Text("Abgewählte Kalender und Listen erscheinen weder im Raster noch in der Tagesliste.")
            .font(.caption2)
            .foregroundStyle(.secondary)

        group(title: "Kalender", kind: .event)
        group(title: "Erinnerungen", kind: .reminder)

        if store.sources.isEmpty {
            Text("Keine Kalender gefunden — fehlt die Berechtigung?")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func group(title: String, kind: SourceInfo.Kind) -> some View {
        let entries = store.sources.filter { $0.kind == kind }
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                ForEach(entries) { source in
                    Toggle(isOn: binding(for: source)) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color(red: source.color.r,
                                            green: source.color.g,
                                            blue: source.color.b))
                                .frame(width: 8, height: 8)
                            Text(source.title).font(.callout).lineLimit(1)
                            Text(source.sourceTitle)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
        }
    }

    private func binding(for source: SourceInfo) -> Binding<Bool> {
        Binding(
            get: { !prefs.isHidden(source.id) },
            set: { shown in
                prefs.setHidden(!shown, for: source.id)
                Task { await store.reload() }
            }
        )
    }
}

// MARK: - Menüleiste

private struct MenuBarSection: View {
    @Environment(Preferences.self) private var prefs
    @Environment(MenuBarLabel.self) private var label

    var body: some View {
        @Bindable var prefs = prefs

        Toggle("Kalenderblatt-Symbol", isOn: $prefs.showIconInMenuBar)
            .onChange(of: prefs.showIconInMenuBar) { label.update() }

        Toggle("Datum als Text", isOn: $prefs.showDateInMenuBar)
            .onChange(of: prefs.showDateInMenuBar) { label.update() }

        if prefs.menuBarWouldBeEmpty {
            Label("Ohne Symbol und ohne Datum wäre der Eintrag leer — MacCal wäre "
                  + "in der Leiste nicht mehr auffindbar. Das Symbol bleibt deshalb.",
                  systemImage: "exclamationmark.triangle")
                .font(.caption2)
                .foregroundStyle(.orange)
        }

        if prefs.showDateInMenuBar {
            VStack(alignment: .leading, spacing: 3) {
                TextField("Datumsformat", text: $prefs.menuBarDateFormat)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: prefs.menuBarDateFormat) { label.update() }
                Text("EEE d. MMM → Mo 21. Sep · d.M.yy → 21.9.26")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }

        Divider()

        Toggle("Nächsten Termin anzeigen", isOn: $prefs.showNextEventInMenuBar)
            .onChange(of: prefs.showNextEventInMenuBar) { label.update() }

        if prefs.showNextEventInMenuBar {
            Stepper("Titel kürzen auf \(prefs.nextEventMaxChars) Zeichen",
                    value: $prefs.nextEventMaxChars, in: 8...60)
                .onChange(of: prefs.nextEventMaxChars) { label.update() }
            Text("Laufende Termine erscheinen hier nie — nur der nächste, der noch "
                 + "nicht begonnen hat. Ist er nicht heute, steht der Tag davor.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Ansicht

private struct PopoverSection: View {
    @Environment(Preferences.self) private var prefs
    @Environment(MenuBarLabel.self) private var label

    var body: some View {
        @Bindable var prefs = prefs

        Toggle("Kalenderwochen anzeigen", isOn: $prefs.showWeekNumbers)
        Toggle("Erledigte Erinnerungen anzeigen", isOn: $prefs.showCompletedReminders)

        Divider()

        Toggle("Fortschritt laufender Termine", isOn: $prefs.showRunningProgress)
            .onChange(of: prefs.showRunningProgress) { label.update() }
        Text("Balken im Popover, Restzeit in der Menüleiste. Nur für Termine, die "
             + "heute begonnen haben und unter 12 Stunden dauern — bei mehrtägigen "
             + "sagt ein Prozentwert nichts.")
            .font(.caption2)
            .foregroundStyle(.secondary)

        Divider()

        Toggle("Hinweis auf Kommendes", isOn: $prefs.showUpcomingBanner)
        if prefs.showUpcomingBanner {
            Stepper("Ab \(prefs.upcomingLeadMinutes) Min. vorher",
                    value: $prefs.upcomingLeadMinutes, in: 5...240, step: 5)
        }

        Divider()

        LoginItemToggle()
    }
}

// MARK: - Start bei der Anmeldung

/// Eigene View, weil der Zustand nicht aus den Einstellungen kommt, sondern
/// bei jedem Erscheinen frisch vom System erfragt wird.
private struct LoginItemToggle: View {
    @State private var state: LoginItem.State = .off
    @State private var failure: String?

    var body: some View {
        Toggle("Bei der Anmeldung starten", isOn: Binding(
            get: { state == .on },
            set: { wanted in
                failure = LoginItem.set(wanted)?.localizedDescription
                // Nicht den gewuenschten Wert uebernehmen, sondern den, der
                // danach tatsaechlich gilt. Ein Schalter, der "an" zeigt,
                // waehrend nichts registriert ist, ist schlimmer als keiner.
                state = LoginItem.state
            }
        ))
        .onAppear { state = LoginItem.state }

        switch state {
        case .needsApproval:
            VStack(alignment: .leading, spacing: 4) {
                Label("macOS wartet auf deine Freigabe.", systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                Button("Systemeinstellungen oeffnen") { LoginItem.openSystemSettings() }
                    .font(.caption2)
            }
        case .unavailable:
            Text("Autostart ist fuer diesen Build nicht verfuegbar. Er verlangt eine "
                 + "App an einem festen Ort — 'make install' legt MacCal nach "
                 + "/Applications.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        default:
            EmptyView()
        }

        if let failure {
            Text(failure).font(.caption2).foregroundStyle(.red)
        }
    }
}
