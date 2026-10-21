import SwiftUI

/// Eingabezeile „Neue Erinnerung" unter der Überschrift AUFGABEN (0.10.0, Michael 2026-10-21).
///
/// Titel tippen, Tag und Uhrzeit per Knopf **oder** im Text („Zahnarzt morgen 15 Uhr"),
/// optional „Dringend". Return sichert, Esc bricht ab. Gespeichert wird in der Standardliste
/// von Apple Erinnerungen (`CalendarStore.createReminder`).
struct QuickReminderField: View {
    let initialDay: Date
    let calendar: Calendar
    var scale: Double = 1.0
    let onSave: (QuickReminder.Draft) async -> String?
    let onDone: () -> Void

    @State private var text = ""
    @State private var day = Date()
    @State private var time: QuickReminder.Time?
    @State private var urgent = false
    @State private var recognized: String?
    @State private var error: String?
    @State private var saving = false
    @State private var showingDayPicker = false
    @State private var showingTimePicker = false
    @FocusState private var focused: Bool

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "EEE d. MMM"
        return f
    }()

    /// Kurz für den Knopf eines eigenen Datums — passt neben die drei festen Knöpfe.
    private static let chipDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "d. MMM"
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            TextField("z. B. „Zahnarzt anrufen morgen 15 Uhr“", text: $text)
                .textFieldStyle(.plain)
                .font(Theme.font(Theme.Size.itemTitle, scale))
                .focused($focused)
                .onSubmit { save() }
                .onExitCommand { onDone() }
                .onChange(of: text) { _, new in applyRecognition(new) }
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 7).fill(.primary.opacity(0.06)))

            if let recognized {
                Label("Erkannt: \(recognized)", systemImage: "wand.and.stars")
                    .font(Theme.font(Theme.Size.hint, scale))
                    .foregroundStyle(Theme.accent)
            }

            chipRow(label: "Tag") {
                ForEach(QuickReminder.DayChoice.allCases, id: \.self) { choice in
                    let value = QuickReminder.day(choice, now: Date(), calendar: calendar)
                    chip(choice.title, selected: calendar.isDate(day, inSameDayAs: value)) { day = value }
                }
                // Anderes Datum (aus dem Text oder dem Monatsblatt) als eigener, markierter Knopf.
                if !isPresetDay {
                    chip(Self.chipDayFormatter.string(from: day), selected: true) { showingDayPicker = true }
                }
                iconChip("calendar", help: "Anderes Datum") { showingDayPicker = true }
                    .popover(isPresented: $showingDayPicker, arrowEdge: .bottom) {
                        DatePicker("", selection: dayBinding, displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.graphical)
                            .environment(\.locale, Locale(identifier: "de_DE"))
                            .padding(10)
                    }
            }

            chipRow(label: "Zeit") {
                chip("Ohne", selected: time == nil) { time = nil }
                ForEach(QuickReminder.presetTimes, id: \.self) { preset in
                    chip(preset.label, selected: time == preset) { time = preset }
                }
                if let time, !QuickReminder.presetTimes.contains(time) {
                    chip(time.label, selected: true) { showingTimePicker = true }
                }
                iconChip("clock", help: "Andere Uhrzeit") { showingTimePicker = true }
                    .popover(isPresented: $showingTimePicker, arrowEdge: .bottom) {
                        DatePicker("Uhrzeit", selection: timeBinding, displayedComponents: .hourAndMinute)
                            .datePickerStyle(.field)
                            .environment(\.locale, Locale(identifier: "de_DE"))
                            .padding(12)
                    }
            }

            HStack(spacing: 8) {
                Button { urgent.toggle() } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "exclamationmark")
                            .font(.system(size: 10 * scale, weight: .heavy))
                            .foregroundStyle(.red)
                        Text("Dringend")
                            .font(Theme.font(Theme.Size.itemTime, scale, weight: urgent ? .semibold : .regular))
                            .foregroundStyle(urgent ? Color.red : Color.primary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(urgent ? Color.red.opacity(0.16) : Theme.accent.opacity(0.07)))
                }
                .buttonStyle(.plain)
                .help("Priorität „Hoch“ in Apple Erinnerungen, dazu Kallis Vollbild-Hinweis zur Uhrzeit")

                if urgent {
                    Text(time == nil ? "Vollbild nur mit Uhrzeit" : "Vollbild um \(time!.label)")
                        .font(Theme.font(Theme.Size.hint, scale))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Button { save() } label: {
                    Text("Sichern")
                        .font(Theme.font(Theme.Size.itemTime, scale, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .foregroundStyle(canSave ? Theme.onAccent : Color.secondary)
                        .background(Capsule().fill(canSave ? Theme.accent : Color.primary.opacity(0.08)))
                }
                .buttonStyle(.plain)
                .disabled(!canSave)
                .help("Return")
            }

            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(Theme.font(Theme.Size.hint, scale))
                    .foregroundStyle(FamilyTheme.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: Theme.cardRadius).fill(Theme.accent.opacity(0.07)))
        .onAppear {
            day = calendar.startOfDay(for: initialDay)
            focused = true
        }
    }

    // MARK: - Teile

    /// `label` nur für Bedienungshilfen — sichtbar erklären die Knöpfe sich selbst (Platz, 21.10.).
    private func chipRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 5) { content() }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(label)
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(Theme.font(Theme.Size.itemTime, scale, weight: selected ? .semibold : .regular))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .foregroundStyle(selected ? Theme.accent : Color.primary)
                .background(Capsule().fill(Theme.accent.opacity(selected ? 0.22 : 0.07)))
        }
        .buttonStyle(.plain)
    }

    private func iconChip(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10 * scale, weight: .medium))
                .frame(width: 22 * scale, height: 18 * scale)
                .foregroundStyle(.secondary)
                .background(Capsule().fill(Theme.accent.opacity(0.07)))
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private var isPresetDay: Bool {
        QuickReminder.DayChoice.allCases.contains {
            calendar.isDate(day, inSameDayAs: QuickReminder.day($0, now: Date(), calendar: calendar))
        }
    }

    private var dayBinding: Binding<Date> {
        Binding(get: { day }, set: { day = calendar.startOfDay(for: $0) })
    }

    private var timeBinding: Binding<Date> {
        Binding(
            get: {
                let t = time ?? QuickReminder.Time(hour: 9, minute: 0)
                return calendar.date(bySettingHour: t.hour, minute: t.minute, second: 0, of: day) ?? day
            },
            set: { new in
                let c = calendar.dateComponents([.hour, .minute], from: new)
                time = QuickReminder.Time(hour: c.hour ?? 9, minute: c.minute ?? 0)
            }
        )
    }

    private var parsedTitle: String {
        QuickReminder.parse(text, now: Date(), calendar: calendar).title
    }

    private var canSave: Bool { !saving && !parsedTitle.isEmpty }

    // MARK: - Abläufe

    /// Erkanntes übernimmt die Knöpfe. Tippt man danach einen Knopf, gilt der Knopf —
    /// bis sich der Text wieder ändert.
    private func applyRecognition(_ new: String) {
        let parsed = QuickReminder.parse(new, now: Date(), calendar: calendar)
        if let d = parsed.day { day = d }
        if let t = parsed.time { time = t }
        var parts: [String] = []
        if let d = parsed.day { parts.append(Self.dayFormatter.string(from: d)) }
        if let t = parsed.time { parts.append(t.label) }
        recognized = parts.isEmpty ? nil : parts.joined(separator: " · ")
        error = nil
    }

    private func save() {
        guard canSave else { return }
        let draft = QuickReminder.Draft(title: parsedTitle, day: day, time: time, urgent: urgent)
        saving = true
        Task {
            let result = await onSave(draft)
            saving = false
            if let result {
                error = result
            } else {
                onDone()
            }
        }
    }
}
