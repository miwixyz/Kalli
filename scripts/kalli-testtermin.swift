// SYNTHETISCH – Testwerkzeug für Sichttests (Gnotchi 0.5.0 „Termine aus Kalli“, 21.10.).
// Legt einen Testtermin an bzw. löscht ihn wieder – löschen nur bei genau passendem Titel.
//
// Bauen:  swiftc -O scripts/kalli-testtermin.swift -o /tmp/kalli-testtermin
// Anlegen: /tmp/kalli-testtermin anlegen <Minuten ab jetzt> "<Titel>" ["<Kalendername>"]  → druckt die Kennung
// Löschen: /tmp/kalli-testtermin loeschen <Kennung> "<Titel>"
import EventKit
import Foundation

let args = CommandLine.arguments
let store = EKEventStore()
let sem = DispatchSemaphore(value: 0)
var granted = false
store.requestFullAccessToEvents { ok, _ in granted = ok; sem.signal() }
sem.wait()
guard granted else { print("FEHLER: kein Kalenderzugriff"); exit(2) }

switch args.dropFirst().first {
case "anlegen":
    guard args.count >= 4, let minutes = Double(args[2]) else { print("Aufruf: anlegen <Minuten> <Titel> [Kalender]"); exit(1) }
    let name = args.count >= 5 ? args[4] : "👊 Michas Kalender"
    guard let cal = store.calendars(for: .event).first(where: { $0.title == name && $0.allowsContentModifications }) else {
        print("FEHLER: Kalender nicht gefunden oder schreibgeschützt"); exit(1)
    }
    var start = Date().addingTimeInterval(minutes * 60)
    start = Date(timeIntervalSince1970: (start.timeIntervalSince1970 / 60).rounded(.down) * 60)
    let e = EKEvent(eventStore: store)
    e.title = args[3]
    e.startDate = start
    e.endDate = start.addingTimeInterval(15 * 60)
    e.calendar = cal
    do { try store.save(e, span: .thisEvent, commit: true) } catch { print("FEHLER: \(error.localizedDescription)"); exit(1) }
    let f = DateFormatter(); f.dateFormat = "HH:mm"
    print("angelegt \(e.eventIdentifier ?? "?") Beginn \(f.string(from: start))")
case "loeschen":
    guard args.count >= 4 else { print("Aufruf: loeschen <Kennung> <Titel>"); exit(1) }
    guard let e = store.event(withIdentifier: args[2]) else { print("nicht gefunden"); exit(1) }
    guard e.title == args[3] else { print("FEHLER: Titel passt nicht – nichts gelöscht"); exit(1) }
    do { try store.remove(e, span: .thisEvent, commit: true) } catch { print("FEHLER: \(error.localizedDescription)"); exit(1) }
    print("gelöscht")
default:
    print("Aufruf: anlegen … | loeschen …"); exit(1)
}
