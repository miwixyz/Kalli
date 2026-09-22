import SwiftUI

@main
struct KalliApp: App {

    @State private var prefs: Preferences
    @State private var store: CalendarStore
    @State private var label: MenuBarLabel
    @State private var updater = Updater()

    init() {
        let p = Preferences()
        let s = CalendarStore(prefs: p)
        _prefs = State(initialValue: p)
        _store = State(initialValue: s)
        _label = State(initialValue: MenuBarLabel(prefs: p, store: s))
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environment(prefs)
                .environment(store)
                .environment(label)
                .environment(updater)
                .tint(Theme.accent)
                .task {
                    // Berechtigung erst beim ersten Öffnen erfragen, nicht beim
                    // Start: Ein Dialog, der ungefragt beim Login aufpoppt, wird
                    // reflexhaft weggeklickt — und dann ist die App still kaputt.
                    // `canPrompt` statt `access == .unknown`: Steht eine der
                    // beiden Berechtigungen auf `notDetermined`, kann ein Dialog
                    // etwas bewirken — sonst nicht.
                    //
                    // Die alte Bedingung war der Fehler vom 2026-09-22: Sobald
                    // EINE Berechtigung schon erteilt war, stand `access` auf
                    // `.partial` statt `.unknown`, und die FEHLENDE wurde nie
                    // angefragt. Unsichtbar obendrein, weil der Hinweis im
                    // Popover an `.denied` hing.
                    // Auch der Nicht-Fall wird protokolliert. „Es passiert
                    // nichts" muss unterscheidbar sein von „es wurde nichts
                    // versucht" — das war am 2026-09-22 nicht unterscheidbar.
                    CalendarStore.logPopoverOpened(canPrompt: store.canPrompt)
                    if store.canPrompt {
                        await store.requestAccess()
                        label.update()
                    }
                }
        } label: {
            // Symbol IMMER zeichnen. Ein reines Text-Label verschwindet
            // spurlos, sobald der Text leer ist -- die App laeuft dann, ist
            // aber unsichtbar und wirkt wie nicht gestartet.
            if label.showIcon {
                Image(nsImage: label.icon)
            }
            if !label.text.isEmpty {
                Text(label.text)
            }
        }
        .menuBarExtraStyle(.window)
    }
}
