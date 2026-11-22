import SwiftUI

/// Nächster Termin an einen Briefkasten fürs Schreibtischgerät (0.17.0). Ab Werk aus.
struct KumikiTerminSettings: View {
    @Environment(KumikiTerminSender.self) private var sender: KumikiTerminSender?
    @AppStorage(KumikiTermin.enabledKey) private var enabled = false
    @AppStorage(KumikiTermin.urlKey) private var savedURL = ""
    @State private var url = ""
    @State private var key = ""
    @State private var feedback: String?

    var body: some View {
        Toggle("Nächsten Termin senden", isOn: $enabled)
            .onChange(of: enabled) { _, on in if on { sender?.send() } }
        SettingsHint("Gesendet werden nur Titel (höchstens \(KumikiTermin.maxTitle) Zeichen) und Beginn des "
                     + "nächsten Termins, alle 5 Minuten und bei jeder Änderung. Keine Teilnehmer, Orte oder Notizen.")
        if enabled {
            TextField("Adresse (https://…/termin)", text: $url)
                .textFieldStyle(.roundedBorder)
                .onAppear { url = savedURL }
            SecureField(KumikiTerminKeychain.exists() ? "Schlüssel (gespeichert, leer = behalten)" : "Schlüssel",
                        text: $key)
                .textFieldStyle(.roundedBorder)
            Button("Speichern") {
                do {
                    if key.isEmpty, KumikiTerminKeychain.exists(), let u = KumikiTermin.validURL(url) {
                        savedURL = u.absoluteString
                    } else {
                        try KumikiTermin.save(url: url, key: key)
                    }
                    key = ""
                    feedback = nil
                    sender?.send()
                } catch {
                    feedback = error.localizedDescription
                }
            }
            if let text = feedback ?? sender?.status {
                SettingsHint(text)
            }
        }
    }
}
