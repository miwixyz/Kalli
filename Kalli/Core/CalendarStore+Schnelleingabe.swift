import Foundation

/// Schnelleingabe aus Gnotchi (G61): eigene Datei, weil `CalendarStore` an der Längengrenze steht.
/// Details zum Speichern: `GnotchiQuickEntry+EventKit`.
///
/// Neu laden läuft **nach** der Antwort an Gnotchi (code-audit 19.11.): Gnotchi wartet nur kurz. Wartete die Antwort
/// auf das volle Neuladen, meldete Gnotchi bei großen Kalendern „Kalli antwortet nicht“, obwohl gespeichert war –
/// und man tippte den Eintrag ein zweites Mal ein. Gespeichert und nachgelesen ist vor der Antwort.
extension CalendarStore {

    /// Legt an und liest nach. Kennung oder Meldung.
    func createQuickEntry(_ entry: GnotchiQuickEntry.Create, calendar: Calendar = .current) async
        -> Result<String, GnotchiQuickEntry.Failure> {
        let result = GnotchiQuickEntry.save(entry, in: store, calendar: calendar)
        if case .success = result { Task { await reload() } }
        return result
    }

    /// Nimmt einen eben angelegten Eintrag zurück. `nil` = weg, sonst die Meldung.
    func removeQuickEntry(identifier: String, kind: GnotchiQuickEntry.Kind) async -> String? {
        let message = GnotchiQuickEntry.remove(identifier: identifier, kind: kind, in: store)
        if message == nil { Task { await reload() } }
        return message
    }
}
