import SwiftUI

// Gruppen und Zeilen der Tagesliste. Eigene Datei seit 0.10.0 (Klappen, „+"), weil
// `PopoverView.swift` sonst über die SwiftLint-Grenze von 650 Zeilen wuchs. Verschoben,
// nicht geändert — nur `private` fiel weg.

/// Eine Gruppe mit Überschrift. Trennlinien nur innerhalb der Gruppe — die
/// Gruppen selbst trennt der Abstand plus die Überschrift.
struct AgendaGroup: View {
    let title: String
    let items: [AgendaItem]
    /// `nil` = nicht zuklappbar („Termine").
    var isCollapsed: Bool? = nil
    var onToggleCollapse: (() -> Void)? = nil
    /// „+" rechts in der Überschrift (nur „Aufgaben").
    var onAdd: (() -> Void)? = nil
    var isAdding: Bool = false
    var addField: AnyView? = nil
    let showProgress: Bool
    var scale: Double = 1.0
    var justCompleted: Set<String> = []
    var oneThingID: String? = nil
    var onToggle: ((AgendaItem) -> Void)? = nil
    var onMakeOneThing: ((AgendaItem) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                if let isCollapsed {
                    // Ganze Überschrift ist der Schalter — ein winziger Pfeil allein wäre schwer zu treffen.
                    Button { onToggleCollapse?() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 8 * scale, weight: .bold))
                                .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                            groupTitle
                            if isCollapsed, !items.isEmpty {
                                Text(verbatim: "\(items.count)")
                                    .font(Theme.font(Theme.Size.groupTitle, scale, weight: .semibold))
                                    .monospacedDigit()
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(.primary.opacity(0.08)))
                                    .padding(.leading, 2)
                            }
                        }
                        .foregroundStyle(.tertiary)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(isCollapsed ? "Aufklappen" : "Zuklappen")
                } else {
                    groupTitle.foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
                if let onAdd {
                    Button { onAdd() } label: {
                        Image(systemName: isAdding ? "xmark" : "plus")
                            .font(.system(size: 10 * scale, weight: .semibold))
                            .frame(width: 18 * scale, height: 16 * scale)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
                    .help(isAdding ? "Abbrechen" : "Neue Erinnerung in Apple Erinnerungen")
                    .accessibilityLabel(Text(isAdding ? "Abbrechen" : "Neue Erinnerung"))
                }
            }
            .padding(.bottom, 5)

            if let addField { addField.padding(.bottom, 6) }

            if isCollapsed != true {
                rows
            }
        }
    }

    private var groupTitle: some View {
        Text(title.uppercased())
            .font(Theme.font(Theme.Size.groupTitle, scale, weight: .semibold))
            .tracking(0.8)
    }

    private var rows: some View {
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            if index > 0 {
                Divider().opacity(0.22).padding(.leading, 18)
            }
            AgendaRow(item: item, showProgress: showProgress, scale: scale,
                      isFading: justCompleted.contains(item.id),
                      isOneThing: item.isReminder && item.id == oneThingID,
                      onToggle: { onToggle?(item) })
                .padding(.vertical, 5)
                .contentShape(Rectangle())
                .contextMenu {
                    if item.isReminder && !item.isCompleted {
                        Button("Als eine Sache in die Leiste", systemImage: "scope") { onMakeOneThing?(item) }
                    }
                }
        }
    }
}

struct AgendaRow: View {
    let item: AgendaItem
    let showProgress: Bool
    var scale: Double = 1.0
    var isFading: Bool = false
    /// Diese Erinnerung steht als „die eine Sache" in der Leiste.
    var isOneThing: Bool = false
    var onToggle: (() -> Void)? = nil

    private let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            // Drei Arten, drei Formen — nicht dieselbe Form in drei Farben.
            // Die Form trägt die Bedeutung auch dann, wenn zwei Kalender
            // zufällig ähnlich eingefärbt sind.
            Group {
                if item.isReminder {
                    // Der Marker ist hier zugleich der Schalter. Ein separater
                    // Knopf daneben waere eine zweite Stelle fuer dieselbe
                    // Information -- das Haekchen IST die Handlung.
                    Button {
                        onToggle?()
                    } label: {
                        Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 12 * scale))
                            .symbolEffect(.bounce, value: item.isCompleted)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(item.isCompleted ? "Häkchen zurücknehmen" : "Als erledigt markieren")
                    .accessibilityLabel(Text(item.isCompleted ? "Häkchen zurücknehmen" : "Als erledigt markieren"))
                } else if item.isAllDay {
                    // Balken = gilt über die ganze Breite des Tages.
                    RoundedRectangle(cornerRadius: 1.5)
                        .frame(width: 9, height: 4)
                } else {
                    Circle().frame(width: 7, height: 7)
                }
            }
            .foregroundStyle(Color(
                red: item.color.r, green: item.color.g, blue: item.color.b
            ))
            .frame(width: 10)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    if item.isUrgent && !item.isCompleted {
                        // Wie Apple Erinnerungen: Priorität vor dem Titel, in Rot.
                        Image(systemName: "exclamationmark")
                            .font(.system(size: 10 * scale, weight: .heavy))
                            .foregroundStyle(.red)
                            .help("Dringend (Priorität „Hoch“)")
                    }
                    Text(item.title)
                        .font(Theme.font(Theme.Size.itemTitle, scale))
                        .strikethrough(item.isCompleted)
                        .foregroundStyle(item.isCompleted ? .secondary : .primary)
                    if isOneThing {
                        Image(systemName: "scope")
                            .font(.system(size: 10 * scale, weight: .semibold))
                            .foregroundStyle(Theme.accent)
                            .help("Steht als die eine Sache in der Menüleiste")
                    }
                }
                let time = item.timeLabel(using: timeFormatter)
                if !time.isEmpty {
                    HStack(spacing: 6) {
                        Text(time)
                            .font(Theme.font(Theme.Size.itemTime, scale))
                            .foregroundStyle(.secondary)
                        if let remaining = item.remainingLabel() {
                            Text(remaining)
                                .font(Theme.font(Theme.Size.hint, scale, weight: .medium))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }
                if showProgress, let progress = item.progress() {
                    ProgressBar(value: progress,
                                color: Color(red: item.color.r, green: item.color.g,
                                             blue: item.color.b),
                                height: 3)
                }
            }
            Spacer(minLength: 0)

            // Nur solange die Zeile nachleuchtet: ein Weg zurueck. Danach
            // bleibt der Kreis selbst der Schalter.
            // Nicht bei Serien: Das Abhaken schiebt dort womoeglich die
            // Faelligkeit weiter, ein Zuruecknehmen traefe dann das naechste
            // Vorkommen (Audit-Fund K-C9, nicht gemessen — siehe
            // CalendarStore.completionConfirmed).
            if isFading && !item.isRecurring {
                Button("Rückgängig") { onToggle?() }
                    .font(Theme.font(Theme.Size.hint, scale, weight: .medium))
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.accent)
            }
        }
        .opacity(isFading ? 0.55 : 1)
        .background {
            if isFading {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Theme.accent.opacity(0.10))
                    .padding(.horizontal, -4)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .leading)))
    }
}
