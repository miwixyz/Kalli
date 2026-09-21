import SwiftUI

@main
struct MacCalApp: App {

    @State private var prefs: Preferences
    @State private var store: CalendarStore
    @State private var label: MenuBarLabel

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
                .task {
                    // Berechtigung erst beim ersten Öffnen erfragen, nicht beim
                    // Start: Ein Dialog, der ungefragt beim Login aufpoppt, wird
                    // reflexhaft weggeklickt — und dann ist die App still kaputt.
                    if store.access == .unknown {
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
