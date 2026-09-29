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
        case help = "Hilfe"
        var id: String { rawValue }
    }

    @State private var tab: Tab = .sources

    var body: some View {
        VStack(spacing: 12) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.large)

            // Die Hilfe bringt ihren eigenen Scrollbereich mit (sie rendert
            // lange Dokumente). Zwei ineinander verschachtelte ScrollViews
            // fangen sich gegenseitig die Scroll-Gesten ab — deshalb bekommt
            // nur der Einstellungsteil hier einen.
            if tab == .help {
                HelpView()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        switch tab {
                        case .sources: SourcesSection()
                        case .menuBar: MenuBarSection()
                        case .popover: PopoverSection()
                        case .help: EmptyView()
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, 2)
                    .padding(.bottom, 4)
                }
                .frame(height: 440)
            }
        }
    }
}

// MARK: - Kalender & Erinnerungslisten

private struct SourcesSection: View {
    @Environment(Preferences.self) private var prefs
    @Environment(CalendarStore.self) private var store
    @Environment(MenuBarLabel.self) private var label

    /// Frisch gelesen, aber **in beobachtbaren Zustand hinein** — genau das
    /// Muster von `LoginItemToggle`.
    ///
    /// In 0.4.3 las die Ansicht `store.eventPermission` direkt im `body`. Das
    /// ist eine `nonisolated var`, die `EKEventStore.authorizationStatus`
    /// aufruft — **kein Teil des Observation-Graphen**. SwiftUI hatte damit
    /// keinen Grund, nach einer Berechtigungsanfrage neu zu zeichnen: Die
    /// Anfrage konnte gelingen, und die Anzeige blieb gleich. Michael: „Abfrage
    /// ist da, es geschieht nach Klick aber nichts."
    @State private var eventState: CalendarStore.Permission = .notDetermined
    @State private var reminderState: CalendarStore.Permission = .notDetermined
    /// Gesetzt, wenn eine Anfrage lief und sich **nichts** geändert hat.
    @State private var promptHadNoEffect = false

    private func refreshPermissions() {
        eventState = store.eventPermission
        reminderState = store.reminderPermission
    }

    var body: some View {
        SettingsGroup(title: "Berechtigungen", symbol: "lock.shield.fill", tint: .green) {
            permissions
        }

        group(title: "Kalender", symbol: "calendar", tint: .red, kind: .event)
        group(title: "Erinnerungen", symbol: "checklist", tint: .orange, kind: .reminder)

        if store.sources.isEmpty {
            // Vorher stand hier eine Frage („fehlt die Berechtigung?"). Der
            // Berechtigungs-Block oben beantwortet sie jetzt.
            SettingsHint("Keine Kalender gefunden. Der Berechtigungs-Stand steht oben.")
        } else {
            SettingsHint("Abgewählte Kalender und Listen erscheinen weder im Raster noch in der Tagesliste.")
                .padding(.leading, 2)
        }
    }

    /// Zustand **und** Handlungsmöglichkeit für beide Berechtigungen.
    ///
    /// Vorher gab es das nicht: Wurde eine Berechtigung entzogen oder war sie
    /// nie erteilt, blieb die Liste leer und die App sagte nur „Keine Kalender
    /// gefunden — fehlt die Berechtigung?". Eine Frage statt einer Antwort, ohne
    /// Weg zur Behebung. (Befund von Michael, 2026-09-22.)
    ///
    /// Der Zustand wird bei jedem Zeichnen **frisch von macOS gelesen**, nicht
    /// gespiegelt — wie bei `LoginItem`.
    @ViewBuilder
    private var permissions: some View {
        permissionRow("Kalender", eventState, reminders: false)
            // Bei jedem Erscheinen frisch von macOS lesen. Der Nutzer kann den
            // Zugriff zwischendurch in den Systemeinstellungen geaendert haben,
            // ohne dass Kalli davon erfaehrt.
            .onAppear { refreshPermissions() }
        permissionRow("Erinnerungen", reminderState, reminders: true)

        if eventState == .notDetermined || reminderState == .notDetermined {
            Button("Fehlende Berechtigung anfragen") {
                Task {
                    let changed = await store.requestAccess()
                    refreshPermissions()
                    promptHadNoEffect = !changed
                    label.update()
                }
            }
            Text("macOS zeigt den Dialog nur einmal. Wurde schon abgelehnt, "
                 + "hilft ausschließlich der Weg über die Systemeinstellungen.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }

        // Ein Knopf, der nichts sichtbar tut, sieht wie ein kaputter Knopf aus.
        // Wenn macOS keinen Dialog gezeigt hat, sagt Kalli das jetzt — statt
        // unverändert dazustehen.
        if promptHadNoEffect {
            VStack(alignment: .leading, spacing: 4) {
                Label("macOS hat keinen Dialog gezeigt.", systemImage: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                Text("Das passiert, wenn die Entscheidung schon einmal getroffen "
                     + "wurde. → ZU TUN: Systemeinstellungen → Datenschutz & "
                     + "Sicherheit → Kalender → Kalli aktivieren.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Button("Systemeinstellungen öffnen") {
                    CalendarStore.openPrivacySettings()
                }
                .font(.caption2)
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func permissionRow(_ title: String, _ state: CalendarStore.Permission,
                               reminders: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: state == .granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(state == .granted ? Color.green : .orange)
            Text("\(title): \(state.label)")
                .font(Theme.font(Theme.Size.itemTime, prefs.layoutScale))
            Spacer()
            // Nur anbieten, wo es auch wirkt. Ein Knopf, der nichts tun kann,
            // ist schlimmer als keiner.
            if state == .denied {
                Button("Systemeinstellungen") {
                    CalendarStore.openPrivacySettings(reminders: reminders)
                }
                .font(Theme.font(Theme.Size.hint, prefs.layoutScale))
            }
        }
    }

    @ViewBuilder
    private func group(title: String, symbol: String, tint: Color,
                       kind: SourceInfo.Kind) -> some View {
        let entries = store.sources.filter { $0.kind == kind }
        if !entries.isEmpty {
            SettingsGroup(title: title, symbol: symbol, tint: tint) {
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
                    // Häkchen wie in Apples Kalender-App: Eine lange Liste von
                    // Schaltern wäre unruhig.
                    .toggleStyle(.checkbox)
                    .controlSize(.regular)
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
    @Environment(CalendarStore.self) private var store

    /// Wird gesetzt, wenn die Mitteilungs-Berechtigung fehlt. Der Schalter
    /// springt dann zurueck — ein Schalter, der „an" zeigt und nichts tut,
    /// waere eine Behauptung.
    @State private var notificationDenied = false

    var body: some View {
        SettingsGroup(title: "Anzeige in der Leiste", symbol: "menubar.rectangle", tint: Theme.accent) {
            display
        }

        SettingsGroup(title: "Termin in der Leiste", symbol: "clock.fill", tint: .indigo) {
            eventInBar
        }

        SettingsGroup(title: "Hinweis vor dem Termin", symbol: "bell.badge.fill", tint: .red) {
            reminderChannels
        }

        SettingsGroup(title: "Vollbild-Hinweis", symbol: "rectangle.bottomhalf.inset.filled", tint: .purple) {
            fullScreen
        }
    }

    @ViewBuilder
    private var display: some View {
        @Bindable var prefs = prefs

        Toggle("Kalli-Symbol anzeigen", isOn: $prefs.showIconInMenuBar)
            .onChange(of: prefs.showIconInMenuBar) { label.update() }

        Toggle("Datum als Text", isOn: $prefs.showDateInMenuBar)
            .onChange(of: prefs.showDateInMenuBar) { label.update() }

        if prefs.menuBarWouldBeEmpty {
            Label("Ohne Symbol und ohne Datum wäre der Eintrag leer — Kalli wäre "
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
                SettingsHint("EEE d. MMM → Mo 21. Sep · d.M.yy → 21.9.26")
            }
        }
    }

    @ViewBuilder
    private var eventInBar: some View {
        @Bindable var prefs = prefs

        // Hieß bis 0.4.7 „Nächsten Termin anzeigen" — und das war seit 0.1.1
        // unwahr: Der Schalter zeigte auch den LAUFENDEN Termin, und ihn
        // abzuwählen ließ den laufenden stehen. Michael am 2026-09-22: „Es muss
        // aber auswählbar sein, dass gar kein Termin angezeigt wird."
        Toggle("Termin in der Leiste anzeigen", isOn: $prefs.showNextEventInMenuBar)
            .onChange(of: prefs.showNextEventInMenuBar) { label.update() }

        if prefs.showNextEventInMenuBar {
            Picker("Erst ab", selection: $prefs.menuBarLeadMinutes) {
                Text("15 Min. vorher").tag(15)
                Text("30 Min. vorher").tag(30)
                Text("1 Stunde vorher").tag(60)
                Text("2 Stunden vorher").tag(120)
            }
            .onChange(of: prefs.menuBarLeadMinutes) { label.update() }

            Stepper("Titel kürzen auf \(prefs.nextEventMaxChars) Zeichen",
                    value: $prefs.nextEventMaxChars, in: 8...60)
                .onChange(of: prefs.nextEventMaxChars) { label.update() }
            SettingsHint("Liegt der nächste Termin weiter weg, bleibt die Leiste schmal. "
                 + "Steht nichts an, zeigt die Leiste den laufenden Termin mit Restzeit "
                 + "— und zwar den, der zuerst endet. Ist der nächste Termin nicht heute, "
                 + "steht der Tag davor.\n\n"
                 + "Abgeschaltet erscheint gar kein Termin in der Leiste, weder ein "
                 + "kommender noch ein laufender. Der Fortschrittsbalken im Popover "
                 + "bleibt davon unberührt — der hängt an \u{201E}Fortschritt laufender Termine\u{201C}.")
        }
    }

    @ViewBuilder
    private var reminderChannels: some View {
        @Bindable var prefs = prefs

        Toggle("Systemmitteilung vor dem Termin", isOn: $prefs.notifyBeforeNextEvent)
            .onChange(of: prefs.notifyBeforeNextEvent) { _, isOn in
                Task {
                    guard isOn else {
                        await store.syncAlerts()   // raeumt geplante Mitteilungen ab
                        return
                    }
                    // Berechtigung ERST beim Einschalten erfragen — nicht beim
                    // Start. Und das Ergebnis messen, nicht annehmen.
                    if await store.requestNotificationPermission() {
                        notificationDenied = false
                        await store.syncAlerts()
                    } else {
                        prefs.notifyBeforeNextEvent = false
                        notificationDenied = true
                    }
                }
            }

        // Zweiter Fall: Erlaubnis war da und wurde später in den
        // Systemeinstellungen entzogen — `syncAlerts` meldet es (K-C11).
        if notificationDenied || (prefs.notifyBeforeNextEvent && store.notificationsBlocked) {
            Label("Mitteilungen sind für Kalli nicht erlaubt. "
                  + "→ Systemeinstellungen › Mitteilungen › Kalli",
                  systemImage: "exclamationmark.triangle")
                .font(.caption2)
                .foregroundStyle(.orange)
                .fixedSize(horizontal: false, vertical: true)
        }

        Toggle("Punkt in der Leiste pulsieren lassen", isOn: $prefs.flashNextEventInMenuBar)
            .onChange(of: prefs.flashNextEventInMenuBar) { label.update() }

        if prefs.notifyBeforeNextEvent || prefs.flashNextEventInMenuBar {
            Picker("Vorlauf", selection: $prefs.alertLeadMinutes) {
                Text("5 Min. vorher").tag(5)
                Text("10 Min. vorher").tag(10)
                Text("30 Min. vorher").tag(30)
            }
            .onChange(of: prefs.alertLeadMinutes) {
                label.update()
                Task { await store.syncAlerts() }
            }

            SettingsHint("Gilt für beide Kanäle. Kalli meldet nur Termine, die im "
                 + "Kalender keinen eigenen Alarm tragen — sonst klingelte es "
                 + "zweimal für denselben Termin.")
        }
    }

    @ViewBuilder
    private var fullScreen: some View {
        @Bindable var prefs = prefs

        Toggle("Vollbild-Hinweis vor dem Termin", isOn: $prefs.fullScreenBeforeEvent)
            .onChange(of: prefs.fullScreenBeforeEvent) { store.syncFullScreenAlerts() }

        if prefs.fullScreenBeforeEvent {
            Picker("Vollbild", selection: $prefs.fullScreenLeadMinutes) {
                Text("Zum Beginn").tag(0)
                Text("1 Min. vorher").tag(1)
                Text("2 Min. vorher").tag(2)
                Text("5 Min. vorher").tag(5)
            }
            .onChange(of: prefs.fullScreenLeadMinutes) { store.syncFullScreenAlerts() }

            SettingsHint("Legt sich über alle Bildschirme, bis du ihn schließt (Esc oder Return). "
                 + "Gilt für alle Termine mit Uhrzeit, auch mit eigenem Kalender-Alarm — "
                 + "nicht für ganztägige und abgelehnte. Steht im Termin ein Web-Link, "
                 + "zeigt der Hinweis \u{201E}Link öffnen\u{201C} mit der Zieladresse.")
        }
    }
}

// MARK: - Ansicht

private struct PopoverSection: View {
    @Environment(Preferences.self) private var prefs
    @Environment(MenuBarLabel.self) private var label

    var body: some View {
        @Bindable var prefs = prefs

        SettingsGroup(title: "Darstellung", symbol: "textformat.size", tint: Theme.accent) {
            Picker("Erscheinungsbild", selection: $prefs.appearanceMode) {
                ForEach(AppearanceMode.allCases) { mode in
                    Label(mode.title, systemImage: mode.symbol).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: prefs.appearanceMode) { prefs.appearanceMode.apply() }
            Picker("Schriftgröße", selection: $prefs.textSizeStep) {
                Text("Sehr klein").tag(0)
                Text("Klein").tag(1)
                Text("Standard").tag(2)
                Text("Groß").tag(3)
                Text("Sehr groß").tag(4)
            }
            SettingsHint("Skaliert Schrift, Raster und Fensterbreite gemeinsam — sonst "
                 + "wächst der Text und das Raster bleibt stehen.")
            Toggle("Kalenderwochen anzeigen", isOn: $prefs.showWeekNumbers)
        }

        SettingsGroup(title: "Tagesliste", symbol: "list.bullet", tint: .teal) {
            Toggle("Erledigte Erinnerungen anzeigen", isOn: $prefs.showCompletedReminders)
            Toggle("Vergangene Termine anzeigen", isOn: $prefs.showPastEvents)
            SettingsHint("Abgeschaltet räumt sich die Liste im Lauf des Tages auf — aber nur "
                 + "heute. Ganztägige Termine und Aufgaben bleiben in jedem Fall sichtbar: "
                 + "Eine überfällige Aufgabe ist nicht erledigt, sondern das Gegenteil davon.")
        }

        SettingsGroup(title: "Laufend und kommend", symbol: "timer", tint: .green) {
            Toggle("Fortschritt laufender Termine", isOn: $prefs.showRunningProgress)
                .onChange(of: prefs.showRunningProgress) { label.update() }
            SettingsHint("Balken im Popover, Restzeit in der Menüleiste. Nur für Termine, die "
                 + "gerade laufen und höchstens 12 Stunden dauern — auch über Mitternacht. "
                 + "Bei mehrtägigen sagt ein Prozentwert nichts.")
            Toggle("Hinweis auf Kommendes", isOn: $prefs.showUpcomingBanner)
            if prefs.showUpcomingBanner {
                Stepper("Ab \(prefs.upcomingLeadMinutes) Min. vorher",
                        value: $prefs.upcomingLeadMinutes, in: 5...240, step: 5)
            }
        }

        SettingsGroup(title: "System", symbol: "power", tint: .gray) {
            LoginItemToggle()
        }
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
                 + "App an einem festen Ort — 'make install' legt Kalli nach "
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
