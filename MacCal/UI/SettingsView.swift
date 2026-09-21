import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            SourcesTab().tabItem { Label("Kalender", systemImage: "calendar") }
            AppearanceTab().tabItem { Label("Anzeige", systemImage: "menubar.rectangle") }
        }
        .frame(width: 440, height: 380)
        // Kein Glas auf dem Fensterkörper — vollflächige Transluzenz mittelt
        // das Hintergrundbild auf seine Durchschnittsfarbe. Siehe GlassBackground.swift.
    }
}

// MARK: - Kalender & Erinnerungslisten

private struct SourcesTab: View {
    @Environment(Preferences.self) private var prefs
    @Environment(CalendarStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Abgewählte Kalender und Listen werden weder im Raster noch in der Tagesliste angezeigt.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(12)

            List {
                section(title: "Kalender", kind: .event)
                section(title: "Erinnerungen", kind: .reminder)
            }
        }
    }

    @ViewBuilder
    private func section(title: String, kind: SourceInfo.Kind) -> some View {
        let entries = store.sources.filter { $0.kind == kind }
        if !entries.isEmpty {
            Section(title) {
                ForEach(entries) { source in
                    Toggle(isOn: binding(for: source)) {
                        HStack(spacing: 7) {
                            Circle()
                                .fill(Color(red: source.color.r,
                                            green: source.color.g,
                                            blue: source.color.b))
                                .frame(width: 9, height: 9)
                            Text(source.title)
                            Text(source.sourceTitle)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
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

private struct AppearanceTab: View {
    @Environment(Preferences.self) private var prefs
    @Environment(MenuBarLabel.self) private var label

    var body: some View {
        @Bindable var prefs = prefs

        Form {
            Section("Menüleiste") {
                TextField("Datumsformat", text: $prefs.menuBarDateFormat)
                    .onChange(of: prefs.menuBarDateFormat) { label.update() }
                Text("Muster wie bei Apple: `EEE d. MMM` → Mo 21. Sep · `d.M.yy` → 21.9.26")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Toggle("Nächsten Termin anzeigen", isOn: $prefs.showNextEventInMenuBar)
                    .onChange(of: prefs.showNextEventInMenuBar) { label.update() }

                if prefs.showNextEventInMenuBar {
                    Stepper(
                        "Titel kürzen auf \(prefs.nextEventMaxChars) Zeichen",
                        value: $prefs.nextEventMaxChars, in: 8...60
                    )
                    .onChange(of: prefs.nextEventMaxChars) { label.update() }
                    Text("Ohne feste Länge springt die Breite der Menüleiste bei jedem Terminwechsel.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Popover") {
                Toggle("Kalenderwochen anzeigen", isOn: $prefs.showWeekNumbers)
                Toggle("Erledigte Erinnerungen anzeigen", isOn: $prefs.showCompletedReminders)
            }

            Section {
                Text("Hell und Dunkel folgen automatisch dem System.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
