import AppKit
import OSLog
import SwiftUI
import WidgetKit

@main
struct KalliApp: App {

    /// Nimmt den Link vom Widget-Klick an (0.18.1): öffnet Apple Kalender am heutigen Tag.
    @NSApplicationDelegateAdaptor(KalliAppDelegate.self) private var appDelegate

    @State private var prefs: Preferences
    @State private var store: CalendarStore
    @State private var label: MenuBarLabel
    @State private var updater = Updater()
    @State private var oneThing: OneThing
    /// Hält den Dienste-Anbieter am Leben (NSApp.servicesProvider hält ihn nicht sicher fest).
    @State private var oneThingService: OneThingService
    /// Nächster Termin in Gnotchis Notch (0.12.0, Gnotchi G26).
    @State private var gnotchiEvents: GnotchiEventSender
    /// Tagesblatt auf dem Schreibtisch (0.14.0), ab Werk aus.
    @State private var deskPad: DeskPadController
    /// Tägliches Pop-up mit den heute fälligen Aufgaben (0.15.0), ab Werk aus.
    @State private var taskDigest: TaskDigest
    /// Nächster Termin für ein Schreibtischgerät über einen Briefkasten (0.17.0), ab Werk aus.
    @State private var kumikiTermin: KumikiTerminSender

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
        let l = MenuBarLabel(prefs: p, store: s)
        _label = State(initialValue: l)
        let o = OneThing(lookup: { [s] id in s.reminderLookup(id: id) })
        let service = OneThingService(oneThing: o)
        _oneThing = State(initialValue: o)
        _oneThingService = State(initialValue: service)
        // Schnelleingabe aus Gnotchi (G61): Gnotchi erkennt, Kalli prüft und speichert.
        let quickEntry = GnotchiQuickEntryService(
            create: { [s] entry in await s.createQuickEntry(entry) },
            remove: { [s] id, kind in await s.removeQuickEntry(identifier: id, kind: kind) })
        let events = GnotchiEventSender(current: { [s] in s.nextEvent },
                                        onRequest: { [quickEntry] obj in await quickEntry.handle(obj) })
        _gnotchiEvents = State(initialValue: events)
        let pad = DeskPadController(prefs: p, store: s)
        _deskPad = State(initialValue: pad)
        let digest = TaskDigest(prefs: p, store: s)
        _taskDigest = State(initialValue: digest)
        let kumiki = KumikiTerminSender(current: { [s] in s.nextEvent })
        _kumikiTermin = State(initialValue: kumiki)
        // Widget „Tagesblatt“ beim Start frisch zeichnen lassen: nach einem Update zeigt es sonst bis
        // zu einer Stunde den zwischengespeicherten Stand der alten Version (gemessen 2026-11-26).
        WidgetCenter.shared.reloadTimelines(ofKind: "KalliTagesblatt")
        // Hell/Dunkel beim Start setzen, erst wenn NSApp steht.
        Task { @MainActor in p.appearanceMode.apply() }
        // Bild-Testkopie (docs/SECURE-DESIGN.md K1, nur Debug-Build): keine Termine an Gnotchi – ihr leerer
        // „nächster Termin“ überschriebe die echte Anzeige –, kein Dienste-Menü, dafür der Befehlskanal.
        guard !Self.startedAsBildKopie(prefs: p, store: s, label: l) else { return }
        Task { @MainActor in events.start() }
        Task { @MainActor in pad.start() }
        Task { @MainActor in kumiki.start() }
        Task { @MainActor in
            digest.start()
            #if DEBUG
            digest.showDemoIfRequested()
            #endif
        }
        // „Als eine Sache in Kalli" im Dienste-Menü (Info.plist NSServices).
        Task { @MainActor in
            NSApp.servicesProvider = service
            NSUpdateDynamicServices()
        }
    }

    private static func startedAsBildKopie(prefs: Preferences, store: CalendarStore, label: MenuBarLabel) -> Bool {
        #if DEBUG
        if BildKopie.isActive {
            Task { @MainActor in DebugBridge.start(prefs: prefs, store: store, label: label) }
            return true
        }
        #endif
        return false
    }

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environment(prefs)
                .environment(store)
                .environment(label)
                .environment(updater)
                .environment(oneThing)
                .environment(kumikiTermin)
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
