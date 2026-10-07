import SwiftUI

/// Eingabefeld für „Die eine Sache" — oben im Kalli-Fenster und im eigenen
/// Leisteneintrag. Return übernimmt, das x leert. Ist die Sache eine
/// Erinnerung, steht darunter, dass sie mit dem Abhaken verschwindet.
struct OneThingField: View {
    @Environment(OneThing.self) private var oneThing
    var scale: Double = 1.0

    @State private var draft = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Image(systemName: "scope")
                    .font(.system(size: 11 * scale, weight: .semibold))
                    .foregroundStyle(oneThing.isSet ? Theme.accent : Color.secondary)
                TextField("Die eine Sache …", text: $draft)
                    .textFieldStyle(.plain)
                    .font(Theme.font(Theme.Size.itemTitle, scale))
                    .focused($focused)
                    .onSubmit { commit() }
                    .help("Erscheint als eigener Eintrag in der Menüleiste. Return übernimmt.")
                if oneThing.isSet || !draft.isEmpty {
                    Button {
                        draft = ""
                        oneThing.clear()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 11 * scale))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Aus der Menüleiste entfernen")
                }
            }
            if oneThing.reminderID != nil {
                Text("Erinnerung — verschwindet, sobald du sie abhakst")
                    .font(Theme.font(Theme.Size.hint, scale))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 17 * scale)
            }
        }
        .onAppear { draft = oneThing.text }
        // Von außen gesetzt (Dienste, Erinnerung, Umbenennung): Feld nachziehen,
        // aber nicht mitten ins Tippen.
        .onChange(of: oneThing.text) { _, new in if !focused { draft = new } }
        // Verlässt man das Feld ohne Return, gilt der Text trotzdem.
        .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
    }

    private func commit() {
        let cleaned = OneThing.clean(draft)
        guard cleaned != oneThing.text else { return }
        // Freier Text löst eine gebundene Erinnerung ab.
        oneThing.set(text: cleaned)
        draft = cleaned
    }
}
