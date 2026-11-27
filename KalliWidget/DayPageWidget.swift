import SwiftUI
import WidgetKit

@main
struct KalliWidgets: WidgetBundle {
    var body: some Widget {
        DayPageWidget()
    }
}

/// Das Tagesblatt als Widget (Michael 2026-11-26: „optional ein Widget“, „Design wie Punkti“):
/// Glasscheibe mit Tagesring und LED-Tageszahl, darunter bzw. daneben die Termine und Aufgaben
/// von heute, in Groß dazu das Monatsraster. Nur anzeigend, ohne Blättern und Abhaken.
struct DayPageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "KalliTagesblatt", provider: DayPageProvider()) { entry in
            DayPageView(entry: entry)
        }
        .configurationDisplayName("Tagesblatt")
        .description("Heute mit Terminen und Aufgaben, im Glas-Look.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

struct DayPageView: View {
    let entry: DayPageEntry
    @Environment(\.widgetFamily) private var family

    private let color = Color.white
    private let calendar = Calendar.current

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let pad = min(w, h) * 0.07
            switch family {
            case .systemSmall:
                PunktiDayDisc(date: entry.date, footer: footer, color: color)
            case .systemMedium:
                HStack(spacing: 0) {
                    PunktiDayDisc(date: entry.date, footer: footer, color: color).frame(width: h, height: h)
                    rows(count: 3, width: w - h - pad, height: h - 2 * pad)
                        .padding(.vertical, pad)
                        .padding(.trailing, pad)
                }
            default:
                VStack(spacing: pad * 0.6) {
                    HStack(spacing: pad) {
                        PunktiDayDisc(date: entry.date, footer: footer, color: color)
                            .frame(width: h * 0.46, height: h * 0.46)
                        PunktiMonthGrid(date: entry.date, color: color)
                            .frame(maxWidth: .infinity)
                            .frame(height: h * 0.40)
                    }
                    rows(count: 3, width: w - 2 * pad, height: h * 0.54 - 2 * pad)
                }
                .padding(pad)
                .frame(width: w, height: h, alignment: .top)
            }
        }
        .containerBackground(for: .widget) { PunktiGlassBackground() }
        // Klick öffnet Apple Kalender am heutigen Tag (über Kalli, siehe CalendarToday).
        .widgetURL(URL(string: "kalli://kalender-heute"))
    }

    /// Zeile unter der Tageszahl: Monat und, was heute ansteht.
    private var footer: String {
        PunktiDayDisc.footer(for: entry.date,
                             openCount: entry.hasAccess ? entry.items.filter { !$0.isCompleted }.count : nil)
    }

    /// Was in die Zeilen kommt: laufende und kommende Termine nach Uhrzeit, dann Aufgaben, dann
    /// Ganztägiges. Vorbei ist vorbei — dafür ist im Widget kein Platz.
    private var shown: [AgendaItem] {
        let open = entry.items.filter { !$0.isCompleted }
        let timed = open.filter { !$0.isReminder && !$0.isAllDay && !$0.isOver(at: entry.date) }
        return timed + open.filter(\.isReminder) + open.filter { $0.isAllDay && !$0.isReminder }
    }

    @ViewBuilder
    private func rows(count: Int, width: CGFloat, height: CGFloat) -> some View {
        let gap = height * 0.05
        let rowH = (height - gap * CGFloat(count - 1)) / CGFloat(count)
        if !entry.hasAccess {
            message(["KALENDER-ZUGRIFF", "IN KALLI ERLAUBEN"], rowH)
        } else if shown.isEmpty {
            message(["HEUTE NICHTS", "MEHR GEPLANT"], rowH)
        } else {
            let visible = Array(shown.prefix(count))
            let more = shown.count - visible.count
            VStack(spacing: gap) {
                ForEach(Array(visible.enumerated()), id: \.offset) { index, item in
                    PunktiDayRow(item: item, now: entry.date, color: color,
                           extra: index == visible.count - 1 && more > 0 ? "+\(more)" : nil)
                        .frame(width: width, height: rowH)
                }
                ForEach(0..<(count - visible.count), id: \.self) { _ in Color.clear.frame(height: rowH) }
            }
        }
    }

    private func message(_ lines: [String], _ rowH: CGFloat) -> some View {
        VStack(spacing: rowH * 0.1) {
            ForEach(lines, id: \.self) { line in
                Text(verbatim: line)
                    .font(.system(size: rowH * 0.26, weight: .medium, design: .monospaced))
                    .tracking(rowH * 0.03)
                    .foregroundStyle(color.opacity(line == lines[0] ? 0.85 : 0.6))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
