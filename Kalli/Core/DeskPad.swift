import Foundation

/// Reine Logik des Schreibtisch-Blatts (0.14.0, Michael 2026-11-15: ein Tagesblatt auf dem
/// Desktop „wie Daypad", dazu Termine und Aufgaben). Hier steht nur, was sich ohne Fenster
/// und ohne EventKit prüfen lässt.
enum DeskPad {

    /// Eine Gruppe des Blatts. Leere Gruppen gibt es nicht — das Blatt hat kein „+".
    struct Section: Identifiable, Equatable {
        let kind: AgendaGroupKind
        let items: [AgendaItem]
        var id: AgendaGroupKind { kind }
    }

    /// Teilt die Einträge eines Tages in dieselben drei Gruppen und dieselbe Reihenfolge wie
    /// die Tagesliste im Popover (`Preferences.agendaOrder`).
    ///
    /// Erledigte Erinnerungen bleiben nur, wenn „Erledigte anzeigen" gilt — oder sie wurden
    /// gerade abgehakt (`keeping`): Eine Zeile, die im Moment des Klicks verschwindet, sieht
    /// aus wie ein Fehlklick (gleiche Regel wie im Popover).
    static func sections(from items: [AgendaItem],
                         order: [AgendaGroupKind],
                         showCompleted: Bool,
                         keeping: Set<String> = []) -> [Section] {
        let shown = items.filter { showCompleted || !$0.isCompleted || keeping.contains($0.id) }
        let byKind: [AgendaGroupKind: [AgendaItem]] = [
            .allDay: shown.filter { $0.isAllDay && !$0.isReminder },
            .timed: shown.filter { !$0.isAllDay && !$0.isReminder },
            .tasks: shown.filter(\.isReminder),
        ]
        return AgendaGroupKind.normalized(order).compactMap { kind in
            guard let list = byKind[kind], !list.isEmpty else { return nil }
            return Section(kind: kind, items: list)
        }
    }

    /// Faktor, mit dem das Blatt gezeichnet wird: die eingestellte Textgröße, aber nie größer, als
    /// der Bildschirm Platz hat (Michael 2026-11-26: auf dem kleinen Bildschirm war das Papierblatt
    /// unten abgeschnitten). Kleiner als die Hälfte wird es nicht, sonst ist die Schrift unlesbar.
    static func fitScale(base: CGSize, scale: Double, available: CGSize) -> Double {
        guard base.width > 0, base.height > 0, available.width > 0, available.height > 0 else { return scale }
        let fit = min(available.width / base.width, available.height / base.height)
        return min(scale, max(fit, 0.5))
    }

    /// Tag um `days` verschoben, immer auf 00:00 Ortszeit. Ohne Ergebnis bleibt der Tag stehen.
    static func shifted(_ day: Date, by days: Int, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: day)
        return calendar.date(byAdding: .day, value: days, to: start) ?? start
    }

    // MARK: - Papierblatt: Blättern

    /// Richtung eines Blattwechsels: nach oben ziehen schlägt das Blatt weg (nächster Tag),
    /// nach unten ziehen holt das vorige zurück.
    enum Flip: Equatable { case next, previous }

    /// Fortschritt des Ziehens, −1…1. Negativ = nach oben (nächster Tag). Ein ganzes Blatt
    /// braucht 80 % der Blatthöhe, damit der Daumen nicht über den Rand muss.
    static func flipProgress(translation: CGFloat, height: CGFloat) -> CGFloat {
        guard height > 0 else { return 0 }
        return max(-1, min(1, translation / (height * 0.8)))
    }

    /// Wird beim Loslassen weitergeblättert? Ja, wenn weit genug gezogen wurde (30 % der Höhe)
    /// oder der Schwung dorthin reicht (60 %). Sonst fällt das Blatt zurück.
    static func flipDecision(translation: CGFloat, predicted: CGFloat, height: CGFloat) -> Flip? {
        guard height > 0 else { return nil }
        let far = abs(translation) > height * 0.3
        let fast = abs(predicted) > height * 0.6 && abs(translation) > 8
        guard far || fast else { return nil }
        let direction = abs(predicted) > abs(translation) ? predicted : translation
        return direction < 0 ? .next : .previous
    }

    // MARK: - Papierblatt: Monatsraster

    /// Wochen des Monats von `day` als Zeilen zu 7 Tagen, Wochenbeginn nach `calendar.firstWeekday`.
    /// Leere Felder vor dem 1. und nach dem letzten Tag sind `nil`.
    static func monthWeeks(for day: Date, calendar: Calendar) -> [[Int?]] {
        guard let interval = calendar.dateInterval(of: .month, for: day),
              let count = calendar.range(of: .day, in: .month, for: day)?.count else { return [] }
        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let lead = (firstWeekday - calendar.firstWeekday + 7) % 7
        var cells: [Int?] = Array(repeating: nil, count: lead) + (1...count).map { Optional($0) }
        while cells.count % 7 != 0 { cells.append(nil) }
        return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<$0 + 7]) }
    }

    /// Kürzel der Wochentage ab Wochenbeginn („M D M D F S S“), dazu die Position des Sonntags.
    static func weekdayInitials(calendar: Calendar) -> (symbols: [String], sundayIndex: Int) {
        let all = calendar.veryShortStandaloneWeekdaySymbols
        let shift = calendar.firstWeekday - 1
        let symbols = Array(all[shift...] + all[..<shift])
        return (symbols, (7 - shift) % 7)
    }

    // MARK: - Papierblatt: Abreißen

    /// Achse einer Ziehbewegung. Erst ab 10 pt Weg entschieden, danach bleibt sie bis zum
    /// Loslassen gleich: Wer nach oben blättert, reißt nicht versehentlich ab.
    enum DragAxis: Equatable { case vertical, horizontal }

    static func dragAxis(_ translation: CGSize) -> DragAxis? {
        guard max(abs(translation.width), abs(translation.height)) >= 10 else { return nil }
        return abs(translation.width) > abs(translation.height) * 1.3 ? .horizontal : .vertical
    }

    /// Fortschritt des seitlichen Ziehens, −1…1 (negativ = nach links). Fast die halbe Blattbreite
    /// ist ein ganzer Ausschlag.
    static func tearProgress(translation: CGFloat, width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        return max(-1, min(1, translation / (width * 0.45)))
    }

    /// Reißt das Blatt beim Loslassen ab? Ab 30 % der Breite oder mit kräftigem Schwung.
    static func tearDecision(translation: CGFloat, predicted: CGFloat, width: CGFloat) -> Bool {
        guard width > 0 else { return false }
        return abs(translation) > width * 0.3 || (abs(predicted) > width * 0.7 && abs(translation) > 20)
    }
}
