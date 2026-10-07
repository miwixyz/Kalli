import AppKit
import OSLog
import SwiftUI

@main
struct KalliApp: App {

    @State private var prefs: Preferences
    @State private var store: CalendarStore
    @State private var label: MenuBarLabel
    @State private var updater = Updater()
    @State private var oneThing: OneThing
    /// Hält den Dienste-Anbieter am Leben (NSApp.servicesProvider hält ihn nicht sicher fest).
    @State private var oneThingService: OneThingService

    init() {
        // Schrift der App-Familie (0.6.0) VOR dem ersten Zeichnen registrieren. Ohne
        // Registrierung fällt SwiftUI still auf die Systemschrift zurück — deshalb
        // wird gemessen, nicht angenommen: Registrierung UND Auflösbarkeit.
        FamilyTheme.app = .kalli
        let registered = FamilyTheme.registerFonts()
        let resolvable = NSFontManager.shared.availableMembers(ofFontFamily: FamilyTheme.fontFamily) != nil
        Logger(subsystem: "com.kalli.app", category: "darstellung").notice(
            "Schrift \(FamilyTheme.fontFamily, privacy: .public): registriert \(registered, privacy: .public), auflösbar \(resolvable, privacy: .public)"
        )

        let p = Preferences()
        let s = CalendarStore(prefs: p)
        _prefs = State(initialValue: p)
        _store = State(initialValue: s)
        _label = State(initialValue: MenuBarLabel(prefs: p, store: s))
        let o = OneThing(lookup: { [s] id in s.reminderLookup(id: id) })
        let service = OneThingService(oneThing: o)
        _oneThing = State(initialValue: o)
        _oneThingService = State(initialValue: service)
        // „Als eine Sache in Kalli" im Dienste-Menü (Info.plist NSServices).
        Task { @MainActor in
            NSApp.servicesProvider = service
            NSUpdateDynamicServices()
        }
        // Hell/Dunkel beim Start setzen, erst wenn NSApp steht.
        Task { @MainActor in p.appearanceMode.apply() }
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environment(prefs)
                .environment(store)
                .environment(label)
                .environment(updater)
                .environment(oneThing)
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
                    } else {
                        // Zwischendurch in den Systemeinstellungen erteilt oder
                        // entzogen? Frisch lesen statt bis zum Neustart falsch
                        // anzeigen (Audit-Fund K-C7).
                        await store.refreshAccess()
                    }
                    label.update()
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

        // „Die eine Sache" (0.7.0): eigener Eintrag, nur solange eine gesetzt ist.
        // Wird er mit ⌘-Ziehen aus der Leiste entfernt, ist die Sache leer.
        MenuBarExtra(isInserted: Binding(get: { oneThing.isSet },
                                         set: { if !$0 { oneThing.clear() } })) {
            OneThingField(scale: prefs.layoutScale)
                .environment(oneThing)
                .tint(Theme.accent)
                .padding(12)
                .frame(width: 300 * prefs.layoutScale)
                .glassSurface(in: RoundedRectangle(cornerRadius: 14))
        } label: {
            Text(oneThing.barText)
        }
        .menuBarExtraStyle(.window)
    }
}
