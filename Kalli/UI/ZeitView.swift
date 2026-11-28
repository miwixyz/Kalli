import SwiftUI

/// Reiter „Zeit“ im Popover (0.21.0, aus MacStd übernommen): laufende Erfassung, Projekte, Übersicht, Export.
struct ZeitView: View {

    @Environment(ZeitErfassung.self) private var zeit
    @Environment(Preferences.self) private var prefs

    @State private var zeitraum: ZeitErfassung.Zeitraum = .woche
    @State private var anchor = Date()
    @State private var newName = ""
    @State private var renaming: UUID?
    @State private var renameText = ""
    @State private var editing: ZeitEintrag?
    @State private var pendingDelete: ZeitProjekt?
    @State private var exportError: String?
    @FocusState private var renameFocus: Bool
    @FocusState private var newFocus: Bool
    @State private var noteText = ""

    var body: some View {
        if let entry = editing {
            ZeitEintragEditor(entry: entry) { editing = nil }
                .environment(zeit)
                .environment(prefs)
        } else {
            VStack(spacing: 12) {
                statusCard
                projectsCard
                overviewCard
                if let message = exportError ?? zeit.errorMessage { errorLine(message) }
                toolsRow
            }
            .confirmationDialog("„\(pendingDelete?.name ?? "")“ mit allen Einträgen löschen?",
                                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                                titleVisibility: .visible) {
                Button("Löschen", role: .destructive) {
                    if let project = pendingDelete { zeit.deleteProject(id: project.id) }
                    pendingDelete = nil
                }
            } message: {
                Text("Das lässt sich nicht rückgängig machen.")
            }
        }
    }

    private func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { Theme.font(size, prefs.layoutScale, weight: weight) }

    // MARK: - Laufende Erfassung

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let project = zeit.activeProject {
                HStack(spacing: 8) {
                    Circle().fill(Color(zeitHex: project.colorHex)).frame(width: 9, height: 9)
                    Text(project.name).font(font(Theme.Size.itemTitle, .semibold)).lineLimit(1)
                    Spacer()
                    Text(zeit.isPaused ? "Pause" : "läuft").font(font(Theme.Size.hint)).foregroundStyle(.secondary)
                }
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(Self.clock(zeit.elapsed(at: context.date)))
                        .font(font(30, .bold)).monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel(Text("Netto-Laufzeit \(Self.clock(zeit.elapsed(at: context.date)))"))
                }
                TextField("Kommentar (optional)", text: $noteText)
                    .textFieldStyle(.plain).font(font(Theme.Size.itemTitle))
                    .padding(.horizontal, 10).frame(height: 28)
                    .background(Capsule(style: .continuous).fill(FamilyTheme.textPrimary.opacity(0.06)))
                    .onChange(of: noteText) { _, new in zeit.setNote(new) }
                    .onAppear { noteText = zeit.sessionNote }
                    .onChange(of: zeit.activeProjectID) { _, _ in noteText = zeit.sessionNote }
                HStack(spacing: 8) {
                    Button { zeit.isPaused ? zeit.resume() : zeit.pause() } label: {
                        Label(zeit.isPaused ? "Weiter" : "Pause", systemImage: zeit.isPaused ? "play.fill" : "pause.fill")
                            .font(font(Theme.Size.itemTime, .medium)).padding(.horizontal, 12).frame(height: 28)
                            .background(Capsule(style: .continuous).fill(FamilyTheme.textPrimary.opacity(0.08)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    Button { zeit.stopByUser() } label: {
                        Label("Stoppen & buchen", systemImage: "stop.fill")
                            .font(font(Theme.Size.itemTime, .semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 12).frame(height: 28)
                            .background(FamilyAccentPill(shape: Capsule(style: .continuous)))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .foregroundStyle(FamilyTheme.textPrimary)
            } else {
                Text("Keine Erfassung läuft.").font(font(Theme.Size.itemTitle, .semibold))
                Text(zeit.projects.isEmpty ? "Lege unten ein Projekt an, dann startest du mit einem Klick."
                                           : "Start mit dem Abspielknopf bei einem Projekt.")
                    .font(font(Theme.Size.itemTime)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .familyContentCard()
    }

    /// Plus und Return legen dasselbe an. Bei leerem Feld springt der Cursor ins Feld, statt still nichts zu tun.
    private func addProject() {
        if zeit.addProject(name: newName) { newName = "" } else { newFocus = true }
    }

    // MARK: - Projekte

    private var projectsCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Projekte").font(font(Theme.Size.dayHeader, .semibold)).foregroundStyle(.secondary)
            ForEach(zeit.projects) { project in projectRow(project) }
            HStack(spacing: 6) {
                Button(action: addProject) {
                    Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                        .frame(width: 22, height: 22).contentShape(Circle())
                        .background(Circle().fill(FamilyTheme.textPrimary.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .help("Projekt anlegen")
                .accessibilityLabel(Text("Projekt anlegen"))
                TextField("Neues Projekt", text: $newName)
                    .textFieldStyle(.plain).font(font(Theme.Size.itemTitle)).focused($newFocus)
                    .onSubmit(addProject)
            }
            .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .familyContentCard()
    }

    private func projectRow(_ project: ZeitProjekt) -> some View {
        let active = zeit.activeProjectID == project.id
        return HStack(spacing: 8) {
            Circle().fill(Color(zeitHex: project.colorHex)).frame(width: 9, height: 9)
            if renaming == project.id {
                TextField("Name", text: $renameText)
                    .textFieldStyle(.plain).font(font(Theme.Size.itemTitle)).focused($renameFocus)
                    .onSubmit { zeit.renameProject(id: project.id, to: renameText); renaming = nil }
                    .onExitCommand { renaming = nil }
            } else {
                Text(project.name).font(font(Theme.Size.itemTitle, active ? .semibold : .regular)).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(ZeitFormat.anzeige(zeit.todayTotal(for: project.id))).font(font(Theme.Size.itemTime)).foregroundStyle(.secondary)
                .help("Heute gebucht")
            Button { zeit.toggle(projectID: project.id) } label: {
                Image(systemName: active ? "stop.fill" : "play.fill").font(.system(size: 11, weight: .semibold))
                    .frame(width: 26, height: 26).contentShape(Circle())
                    .foregroundStyle(active ? Color.white : FamilyTheme.textPrimary)
                    .background { if active { FamilyAccentPill(shape: Circle()) } else { Circle().fill(FamilyTheme.textPrimary.opacity(0.08)) } }
            }
            .buttonStyle(.plain)
            .help(active ? "Stoppen und buchen" : "Erfassung starten")
            .accessibilityLabel(Text(active ? "\(project.name) stoppen" : "\(project.name) starten"))
        }
        .contentShape(Rectangle())
        .onTapGesture { if renaming != project.id { zeit.toggle(projectID: project.id) } }
        .contextMenu {
            Button("Umbenennen") { renameText = project.name; renaming = project.id; renameFocus = true }
            Button("Löschen (mit allen Einträgen) …", role: .destructive) { pendingDelete = project }
        }
    }

    // MARK: - Übersicht

    private var interval: DateInterval? { ZeitErfassung.interval(zeitraum, containing: anchor) }

    private var overviewCard: some View {
        let entries = interval.map { zeit.entries(in: $0) } ?? []
        let totals = interval.map { zeit.totalsByProject(in: $0) } ?? []
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                GlassPillBar(items: ZeitErfassung.Zeitraum.allCases, selection: zeitraum, label: { Text($0.titel) },
                             onSelect: { zeitraum = $0 })
                Spacer(minLength: 0)
                stepButton("chevron.left", "Zurück") { anchor = ZeitErfassung.shift(anchor, zeitraum, by: -1) }
                stepButton("chevron.right", "Weiter") { anchor = ZeitErfassung.shift(anchor, zeitraum, by: 1) }
            }
            Text(periodTitle).font(font(Theme.Size.dayHeader, .semibold)).foregroundStyle(.secondary)
            if entries.isEmpty {
                Text("Keine Einträge in diesem Zeitraum.").font(font(Theme.Size.itemTitle)).foregroundStyle(.tertiary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(totals, id: \.project.id) { row in
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Circle().fill(Color(zeitHex: row.project.colorHex)).frame(width: 7, height: 7)
                                    Text(row.project.name).font(font(Theme.Size.itemTitle, .semibold)).lineLimit(1)
                                    Spacer()
                                    Text(ZeitFormat.anzeige(row.total)).font(font(Theme.Size.itemTitle, .semibold)).monospacedDigit()
                                }
                                ForEach(entries.filter { $0.projectID == row.project.id }) { entryRow($0) }
                            }
                        }
                    }
                }
                // minHeight ist der Punkt: eine ScrollView hat keine eigene Höhe und fällt im VStack sonst auf 0 zusammen
                // (0.21.0: Liste unsichtbar, nur „Summe“ stand da).
                .frame(minHeight: min(listHeight(totals: totals.count, entries: entries), 260 * prefs.layoutScale),
                       maxHeight: 260 * prefs.layoutScale)
                HStack {
                    Text("Summe").font(font(Theme.Size.itemTime, .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Text(ZeitFormat.anzeige(totals.reduce(0) { $0 + $1.total })).font(font(Theme.Size.itemTime, .semibold)).monospacedDigit()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .familyContentCard()
    }

    /// Geschätzte Höhe der Liste (Projektzeile 22, Timerzeile 22, Kommentarzeile 14 je Kommentar, Abstände 10).
    private func listHeight(totals: Int, entries: [ZeitEintrag]) -> CGFloat {
        let notes = entries.filter { !$0.note.isEmpty }.count
        return (CGFloat(totals) * 32 + CGFloat(entries.count) * 22 + CGFloat(notes) * 14) * prefs.layoutScale
    }

    private func stepButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                .frame(width: 26, height: 26).contentShape(Circle())
                .background(Circle().fill(FamilyTheme.textPrimary.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .foregroundStyle(FamilyTheme.textPrimary)
        .accessibilityLabel(Text(label))
    }

    private func entryRow(_ entry: ZeitEintrag) -> some View {
        Button { editing = entry } label: {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 8) {
                    Text(Self.dayTime.string(from: entry.start)).font(font(Theme.Size.itemTime)).foregroundStyle(.secondary).monospacedDigit()
                    Spacer()
                    Text(ZeitFormat.anzeige(entry.netDuration)).font(font(Theme.Size.itemTime)).monospacedDigit()
                }
                if !entry.note.isEmpty {
                    Text(entry.note).font(font(Theme.Size.itemTime)).foregroundStyle(.primary.opacity(0.8)).lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.vertical, 3).padding(.leading, 13).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Eintrag bearbeiten")
    }

    private var periodTitle: String {
        guard let interval else { return "" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        if zeitraum == .monat {
            f.dateFormat = "LLLL yyyy"
            return f.string(from: interval.start).capitalized
        }
        f.dateFormat = "d. MMM"
        let a = f.string(from: interval.start), b = f.string(from: interval.end.addingTimeInterval(-1))
        f.dateFormat = "yyyy"
        return "KW \(ZeitErfassung.calendar.component(.weekOfYear, from: interval.start)): \(a) – \(b) \(f.string(from: interval.start))"
    }

    // MARK: - Export, Ton, Meldung

    private var toolsRow: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(ZeitExport.Format.allCases) { format in
                    Button(format.titel) { export(format) }
                }
            } label: {
                Label("Exportieren", systemImage: "square.and.arrow.up").font(font(Theme.Size.itemTime))
            }
            .menuStyle(.borderlessButton).fixedSize()
            .disabled(interval.map { zeit.entries(in: $0).isEmpty } ?? true)
            .help("Einträge des angezeigten Zeitraums speichern")
            Spacer()
            @Bindable var prefs = prefs
            Toggle("Ton", isOn: $prefs.zeitSound).toggleStyle(.switch).controlSize(.mini)
                .font(font(Theme.Size.itemTime))
                .help("Ton beim Starten und Stoppen per Knopf")
        }
        .padding(.horizontal, 6)
    }

    private func errorLine(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Label(message, systemImage: "exclamationmark.triangle")
                .font(font(Theme.Size.hint)).foregroundStyle(FamilyTheme.warning)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("OK") { exportError = nil; zeit.errorMessage = nil }.buttonStyle(.plain).font(font(Theme.Size.hint, .semibold))
        }
    }

    private func export(_ format: ZeitExport.Format) {
        guard let interval else { return }
        let text = ZeitExport.text(format: format, entries: zeit.entries(in: interval), projects: zeit.projects, titel: periodTitle)
        exportError = ZeitExport.speichern(format: format, text: text, vorschlag: "Arbeitszeiten \(periodTitle)".replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "/", with: "-"))
    }

    // MARK: - Formate

    static func clock(_ interval: TimeInterval) -> String {
        let s = Int(interval)
        return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60)
    }

    private static let dayTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "E d.M. HH:mm"
        return f
    }()
}

extension Color {
    /// Projektfarbe aus „RRGGBB“. Unlesbarer Wert → Akzent.
    init(zeitHex: String) {
        guard zeitHex.count == 6, let v = UInt32(zeitHex, radix: 16) else { self = Theme.accent; return }
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}
