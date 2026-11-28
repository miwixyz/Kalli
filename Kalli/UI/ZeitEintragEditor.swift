import SwiftUI

/// Eintrag nachträglich bearbeiten (im Popover statt als Fenster, damit das Popover nicht schließt).
struct ZeitEintragEditor: View {

    @Environment(ZeitErfassung.self) private var zeit
    @Environment(Preferences.self) private var prefs

    let entry: ZeitEintrag
    let close: () -> Void

    @State private var projectID = UUID()
    @State private var start = Date()
    @State private var end = Date()
    @State private var note = ""
    @State private var pauses: [ZeitPause] = []
    @State private var error: String?
    @State private var confirmDelete = false

    private func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { Theme.font(size, prefs.layoutScale, weight: weight) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Eintrag bearbeiten").font(font(Theme.Size.itemTitle, .semibold))
            Picker("Projekt", selection: $projectID) {
                ForEach(zeit.projects) { Text($0.name).tag($0.id) }
            }
            DatePicker("Von", selection: $start, displayedComponents: [.date, .hourAndMinute])
            DatePicker("Bis", selection: $end, displayedComponents: [.date, .hourAndMinute])
            TextField("Kommentar", text: $note, axis: .vertical).lineLimit(1...3).textFieldStyle(.roundedBorder)
            HStack {
                Text("Pausen").font(font(Theme.Size.dayHeader, .semibold)).foregroundStyle(.secondary)
                Spacer()
                Button { addPause() } label: { Label("Pause", systemImage: "plus.circle.fill").font(font(Theme.Size.itemTime)) }
                    .buttonStyle(.plain)
            }
            ForEach(pauses) { pause in
                HStack(spacing: 6) {
                    DatePicker("Beginn", selection: binding(pause.id, \.start), displayedComponents: [.hourAndMinute]).labelsHidden()
                    Text("–")
                    DatePicker("Ende", selection: binding(pause.id, \.end), displayedComponents: [.hourAndMinute]).labelsHidden()
                    Spacer()
                    Button { pauses.removeAll { $0.id == pause.id } } label: { Image(systemName: "trash") }.buttonStyle(.plain)
                        .accessibilityLabel(Text("Pause entfernen"))
                }
            }
            if let error {
                Text(error).font(font(Theme.Size.hint)).foregroundStyle(FamilyTheme.warning).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Löschen", role: .destructive) { confirmDelete = true }
                    .confirmationDialog("Diesen Eintrag löschen?", isPresented: $confirmDelete) {
                        Button("Löschen", role: .destructive) { zeit.deleteEntry(id: entry.id); close() }
                    }
                Spacer()
                Button("Abbrechen", action: close).keyboardShortcut(.cancelAction)
                Button("Speichern", action: save).keyboardShortcut(.defaultAction)
            }
        }
        .font(font(Theme.Size.itemTitle))
        .padding(14)
        .familyContentCard()
        .onAppear {
            projectID = zeit.projects.contains { $0.id == entry.projectID } ? entry.projectID : (zeit.projects.first?.id ?? entry.projectID)
            start = entry.start; end = entry.end; note = entry.note
            pauses = entry.pauses.sorted { $0.start < $1.start }
        }
    }

    private func binding(_ id: UUID, _ key: WritableKeyPath<ZeitPause, Date>) -> Binding<Date> {
        Binding(get: { pauses.first { $0.id == id }?[keyPath: key] ?? Date() },
                set: { value in if let i = pauses.firstIndex(where: { $0.id == id }) { pauses[i][keyPath: key] = value } })
    }

    private func addPause() {
        let lo = min(start, end), span = max(start, end).timeIntervalSince(lo)
        guard span > 1 else { return }
        let from = lo.addingTimeInterval(span / 2)
        pauses.append(ZeitPause(start: from, end: min(from.addingTimeInterval(15 * 60), lo.addingTimeInterval(span))))
    }

    private func save() {
        guard pauses.allSatisfy({ $0.end > $0.start }) else { error = "Jede Pause braucht ein Ende nach dem Beginn."; return }
        zeit.errorMessage = nil
        let edited = ZeitEintrag(id: entry.id, projectID: projectID, start: start, end: end, note: note, pauses: pauses)
        if zeit.update(edited) {
            close()
        } else {
            error = zeit.errorMessage ?? "Speichern nicht möglich."
        }
    }
}
