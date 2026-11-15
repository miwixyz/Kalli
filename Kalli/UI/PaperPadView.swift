import SwiftUI

/// Das Papierblatt (0.14.0): ein Tagesabreißblock auf dem Schreibtisch — Blatt auf einem Brett
/// mit zwei Ringen, in Kallis Farben und Schrift statt Marineblau und Antiqua. Nach oben ziehen
/// schlägt das Blatt über die Ringe weg, nach unten holt das vorige zurück, Doppelklick auf die
/// Zahl springt auf heute. Auf dem Blatt stehen die Termine und Aufgaben des Tages.
///
/// Die Maße sind Punkte bei Textgröße „normal“ und werden mit `layoutScale` skaliert.
struct PaperPadView: View {
    @Environment(Preferences.self) private var prefs
    @Environment(CalendarStore.self) private var store

    @State private var day = Calendar.current.startOfDay(for: Date())
    /// `false` = das Blatt zeigt immer den aktuellen Tag und springt um Mitternacht mit.
    @State private var pinned = false
    @State private var items: [AgendaItem] = []
    @State private var justCompleted: Set<String> = []
    @State private var toggleError: String?
    /// Blattfortschritt, −1…1. Negativ: aktuelles Blatt wird nach oben weggeschlagen.
    /// Positiv: das vorige Blatt kommt von oben zurück.
    @State private var flip: CGFloat = 0
    /// Seitliches Abreißen: −1…1 (Richtung = Vorzeichen), und danach das Fallen 0…1.
    @State private var tear: CGFloat = 0
    @State private var fall: CGFloat = 0
    @State private var axis: DeskPad.DragAxis?
    @State private var busy = false

    private let calendar = Calendar.current
    private var scale: Double { prefs.layoutScale }

    private enum Metrics {
        static let board = CGSize(width: 340, height: 580)
        static let pageInsetTop: CGFloat = 32
        static let pageInset: CGFloat = 16
        static var page: CGSize {
            CGSize(width: board.width - 2 * pageInset, height: board.height - pageInsetTop - pageInset)
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            board
            pages
                .frame(width: Metrics.page.width * scale, height: Metrics.page.height * scale)
                .padding(.top, Metrics.pageInsetTop * scale)
            strip
        }
        .frame(width: Metrics.board.width * scale, height: Metrics.board.height * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Nächster Tag") { turn(.next) }
        .accessibilityAction(named: "Vorheriger Tag") { turn(.previous) }
        .accessibilityAction(named: "Blatt abreißen") { tearOff() }
        .contextMenu {
            // Das Blatt liegt hinter den Fenstern; der Weg über Popover und Einstellungen ist weit.
            Button("Tagesblatt ausblenden", systemImage: "eye.slash") { prefs.deskPadEnabled = false }
        }
        .task(id: "\(day.timeIntervalSince1970)-\(store.revision)") {
            if !pinned {
                let today = calendar.startOfDay(for: Date())
                if today != day { day = today; return }
            }
            items = await store.itemsAround(day, span: 1, calendar: calendar)
        }
    }

    // MARK: - Brett und Ringe

    private var board: some View {
        let shape = RoundedRectangle(cornerRadius: 26 * scale, style: .continuous)
        return shape
            .fill(LinearGradient(colors: [Color(light: 0x4A5BA8, dark: 0x2B3563),
                                          Color(light: 0x34428A, dark: 0x1C2349)],
                                 startPoint: .top, endPoint: .bottom))
            .overlay(shape.strokeBorder(.white.opacity(0.18), lineWidth: 1))
            .overlay(shape.inset(by: 5 * scale)
                .strokeBorder(.white.opacity(0.10), style: StrokeStyle(lineWidth: 1, dash: [3, 4])))
            .movesWindow()
    }

    /// Dünner Klebestreifen in Kalli-Indigo über dem Blattkopf (Michael 2026-11-15: keine Ringe,
    /// stattdessen Perforation). Er bleibt im Brett; das Blatt darunter hat die Abrisskante.
    private var strip: some View {
        Rectangle()
            .fill(Theme.accent)
            .overlay(alignment: .bottom) { Rectangle().fill(.black.opacity(0.18)).frame(height: 1) }
            .frame(width: Metrics.page.width * scale, height: 6 * scale)
            .padding(.top, (Metrics.pageInsetTop - 7) * scale)
            .allowsHitTesting(false)
    }

    // MARK: - Blätter

    private var pages: some View {
        ZStack {
            // Ein paar Blätter darunter geben dem Block Dicke.
            ForEach([2, 1], id: \.self) { depth in
                RoundedRectangle(cornerRadius: 8 * scale, style: .continuous)
                    .fill(PaperPage.paper.opacity(0.9))
                    .overlay(RoundedRectangle(cornerRadius: 8 * scale, style: .continuous)
                        .strokeBorder(.black.opacity(0.08), lineWidth: 0.5))
                    .padding(.horizontal, CGFloat(depth) * 2 * scale)
                    .offset(y: CGFloat(depth) * 3 * scale)
            }
            if flip < 0 || tear != 0 { page(for: DeskPad.shifted(day, by: 1, calendar: calendar)) } else { page(for: day) }
            if tear != 0 {
                page(for: day).torn(progress: abs(tear), fall: fall, sign: tear > 0 ? 1 : -1, scale: scale)
            } else if flip < 0 {
                page(for: day).flipped(progress: -flip, scale: scale)
            } else if flip > 0 {
                page(for: DeskPad.shifted(day, by: -1, calendar: calendar)).flipped(progress: 1 - flip, scale: scale)
            }
        }
        .gesture(dragGesture)
    }

    private func page(for date: Date) -> some View {
        PaperPage(day: date,
                  items: items.filter { CalendarStore.occurs($0, on: date, calendar: calendar) },
                  scale: scale,
                  showCompleted: prefs.showCompletedReminders,
                  order: prefs.agendaOrder,
                  showProgress: prefs.showRunningProgress,
                  justCompleted: justCompleted,
                  toggleError: toggleError,
                  onToggle: { toggle($0) },
                  onToday: { goToday() })
    }

    // MARK: - Ziehen und Blättern

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard !busy else { return }
                if axis == nil { axis = DeskPad.dragAxis(value.translation) }
                switch axis {
                case .horizontal:
                    tear = DeskPad.tearProgress(translation: value.translation.width,
                                                width: Metrics.page.width * scale)
                case .vertical:
                    flip = DeskPad.flipProgress(translation: value.translation.height,
                                                height: Metrics.page.height * scale)
                case nil:
                    break
                }
            }
            .onEnded { value in
                let used = axis
                axis = nil
                guard !busy else { return }
                switch used {
                case .horizontal:
                    if DeskPad.tearDecision(translation: value.translation.width,
                                            predicted: value.predictedEndTranslation.width,
                                            width: Metrics.page.width * scale) {
                        tearOff()
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { tear = 0 }
                    }
                case .vertical:
                    if let decision = DeskPad.flipDecision(translation: value.translation.height,
                                                           predicted: value.predictedEndTranslation.height,
                                                           height: Metrics.page.height * scale) {
                        turn(decision)
                    } else {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { flip = 0 }
                    }
                case nil:
                    break
                }
            }
    }

    /// Blatt abreißen: schwingt am oberen Eck aus, fällt nach unten weg, dann liegt der nächste
    /// Tag da. Wie beim Umschlagen steht das nächste Blatt schon darunter.
    private func tearOff() {
        guard !busy else { return }
        busy = true
        let sign: CGFloat = tear < 0 ? -1 : 1
        if tear == 0 { tear = 0.001 * sign }
        withAnimation(.easeIn(duration: 0.55), completionCriteria: .logicallyComplete) {
            tear = sign
            fall = 1
        } completion: {
            day = DeskPad.shifted(day, by: 1, calendar: calendar)
            pinned = !calendar.isDateInToday(day)
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                tear = 0
                fall = 0
            }
            busy = false
        }
    }

    /// Blatt zu Ende umschlagen, dann den Tag wechseln. Das Blatt darunter zeigt schon den
    /// neuen Tag; beim Umschalten (`flip = 0` ohne Animation) ändert sich im Bild nichts.
    private func turn(_ direction: DeskPad.Flip) {
        guard !busy else { return }
        busy = true
        let target: CGFloat = direction == .next ? -1 : 1
        // Ein Tipp ohne Ziehen (Bedienungshilfen) startet bei 0 auf der richtigen Seite.
        if flip == 0 { flip = direction == .next ? -0.001 : 0.001 }
        withAnimation(.easeIn(duration: 0.32), completionCriteria: .logicallyComplete) {
            flip = target
        } completion: {
            day = DeskPad.shifted(day, by: direction == .next ? 1 : -1, calendar: calendar)
            pinned = !calendar.isDateInToday(day)
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { flip = 0 }
            busy = false
        }
    }

    private func goToday() {
        guard !busy else { return }
        let today = calendar.startOfDay(for: Date())
        guard today != day else { return }
        let direction: DeskPad.Flip = today > day ? .next : .previous
        // Sprung: erst auf den Tag davor/danach, dann ein Blatt umschlagen — sieht aus wie ein Blättern,
        // ohne dass ein Monat voller Blätter vorbeifliegt.
        day = DeskPad.shifted(today, by: direction == .next ? -1 : 1, calendar: calendar)
        pinned = false
        turn(direction)
    }

    /// Wie im Popover: abhaken, kurz sichtbar lassen, dann ausblenden.
    private func toggle(_ item: AgendaItem) {
        let wasCompleted = item.isCompleted
        Task {
            if let error = await store.setCompleted(!wasCompleted, for: item) {
                toggleError = error
                return
            }
            toggleError = nil
            items = await store.itemsAround(day, span: 1, calendar: calendar)
            guard !wasCompleted else {
                withAnimation { _ = justCompleted.remove(item.id) }
                return
            }
            withAnimation(.easeOut(duration: 0.2)) { _ = justCompleted.insert(item.id) }
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.easeInOut(duration: 0.35)) { _ = justCompleted.remove(item.id) }
        }
    }
}

// MARK: - Blatt umschlagen

private extension View {
    /// Das Blatt hängt an seiner Oberkante (den Ringen) und klappt nach hinten weg: bei 0 liegt es
    /// flach, bei 1 steht es senkrecht zur Blickrichtung und verschwindet. Dazu dunkler und mit
    /// Schatten auf das Blatt darunter.
    func flipped(progress: CGFloat, scale: Double) -> some View {
        let p = max(0, min(1, progress))
        return self
            .overlay(LinearGradient(colors: [.black.opacity(0.0), .black.opacity(0.35 * p)],
                                    startPoint: .top, endPoint: .bottom)
                .clipShape(RoundedRectangle(cornerRadius: 8 * scale, style: .continuous))
                .allowsHitTesting(false))
            .rotation3DEffect(.degrees(-90 * p), axis: (x: 1, y: 0, z: 0), anchor: .top, perspective: 0.45)
            .shadow(color: .black.opacity(0.30 * p), radius: 10 * scale, y: 8 * scale)
            .opacity(p >= 0.999 ? 0 : 1)
    }
}

private extension View {
    /// Abgerissenes Blatt: hängt am oberen Eck, schwingt aus (`progress`, bis 22°), dann fällt es
    /// (`fall`) nach unten, kippt weiter und blendet am Ende aus.
    func torn(progress: CGFloat, fall: CGFloat, sign: CGFloat, scale: Double) -> some View {
        let p = max(0, min(1, progress))
        let f = max(0, min(1, fall))
        return self
            .rotationEffect(.degrees(sign * (22 * p + 28 * f)),
                            anchor: sign > 0 ? .topLeading : .topTrailing)
            .offset(x: sign * 70 * f * scale, y: 760 * f * f * scale)
            .shadow(color: .black.opacity(0.30 * p), radius: 8 * scale, x: sign * 3, y: 6 * scale)
            .opacity(1 - max(0, (f - 0.65) / 0.35))
    }
}

// MARK: - Ein Blatt

/// Ein Blatt: Monat und Jahr, große Zahl, Wochentag, darunter die Liste des Tages, unten das
/// Monatsraster mit dem Tag eingekreist. Mondphase, Tag des Jahres und Kalenderwoche gibt es
/// bewusst nicht (Michael, 2026-11-15: Zahl, Monatsraster und Liste).
struct PaperPage: View {
    let day: Date
    let items: [AgendaItem]
    let scale: Double
    let showCompleted: Bool
    let order: [AgendaGroupKind]
    let showProgress: Bool
    let justCompleted: Set<String>
    let toggleError: String?
    var onToggle: (AgendaItem) -> Void = { _ in }
    var onToday: () -> Void = {}

    static let paper = Color(light: 0xFAF7F0, dark: 0x252833)
    static let ink = Color(light: 0x1E2433, dark: 0xECEFF6)
    private let calendar = Calendar.current

    private let monthFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "MMMM"
        return f
    }()
    private let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "EEEE"
        return f
    }()

    private var isToday: Bool { calendar.isDateInToday(day) }

    private var sections: [DeskPad.Section] {
        DeskPad.sections(from: items, order: order, showCompleted: showCompleted, keeping: justCompleted)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Text(verbatim: "\(calendar.component(.day, from: day))")
                .font(Theme.font(72, scale, weight: .bold))
                .foregroundStyle(isToday ? Theme.accent : Self.ink)
                .frame(maxWidth: .infinity)
                .padding(.top, 2 * scale)
                .onTapGesture(count: 2) { onToday() }
                .help("Doppelklick: zurück zu heute")
            Text(weekdayFormatter.string(from: day).uppercased())
                .font(Theme.font(12, scale, weight: .semibold))
                .tracking(7)
                .foregroundStyle(Self.ink.opacity(0.75))
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8 * scale)
            Rectangle().fill(Self.ink.opacity(0.12)).frame(height: 0.75)
            list
            Spacer(minLength: 0)
            MiniMonth(day: day, scale: scale, calendar: calendar)
        }
        .padding(.horizontal, 18 * scale)
        .padding(.top, 22 * scale)
        .padding(.bottom, 12 * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PerforatedPage(radius: 8 * scale, notch: 2.6 * scale).fill(Self.paper))
        .overlay(alignment: .top) { perforation }
        .clipShape(PerforatedPage(radius: 8 * scale, notch: 2.6 * scale))
        .overlay(PerforatedPage(radius: 8 * scale, notch: 2.6 * scale)
            .stroke(.black.opacity(0.10), lineWidth: 0.5))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: "\(weekdayFormatter.string(from: day)), \(calendar.component(.day, from: day)). \(monthFormatter.string(from: day))"))
    }

    private var header: some View {
        VStack(spacing: 5 * scale) {
            HStack {
                Text(monthFormatter.string(from: day).uppercased())
                    .font(Theme.font(11, scale, weight: .bold))
                    .tracking(3.2)
                    .foregroundStyle(Theme.accent)
                Spacer()
                Text(verbatim: "\(calendar.component(.year, from: day))")
                    .font(Theme.font(11, scale, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(Self.ink.opacity(0.75))
            }
            VStack(spacing: 2) {
                Rectangle().fill(Theme.accent).frame(height: 1.2)
                Rectangle().fill(Theme.accent.opacity(0.55)).frame(height: 0.6)
            }
        }
    }

    /// Gepunktete Linie unter den Aussparungen: hier reißt das Blatt ab.
    private var perforation: some View {
        Rectangle()
            .stroke(Self.ink.opacity(0.28), style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [0.1, 4 * scale]))
            .frame(height: 1)
            .padding(.horizontal, 6 * scale)
            .padding(.top, 8 * scale)
    }

    @ViewBuilder
    private var list: some View {
        if sections.isEmpty {
            Text("Nichts geplant.")
                .font(Theme.font(Theme.Size.itemTitle, scale))
                .foregroundStyle(.tertiary)
                .padding(.top, 10 * scale)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 8 * scale) {
                    ForEach(sections) { section in
                        AgendaGroup(title: section.kind.title, items: section.items,
                                    showProgress: showProgress, scale: scale * 0.92,
                                    justCompleted: justCompleted, hideAllDayLabel: true,
                                    onToggle: { onToggle($0) })
                    }
                    if let toggleError {
                        Text(toggleError).font(Theme.font(Theme.Size.hint, scale)).foregroundStyle(.red)
                    }
                }
                .padding(.top, 8 * scale)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.hidden)
        }
    }
}

/// Das Monatsraster am Fuß des Blatts, der Tag des Blatts eingekreist.
private struct MiniMonth: View {
    let day: Date
    let scale: Double
    let calendar: Calendar

    var body: some View {
        let weeks = DeskPad.monthWeeks(for: day, calendar: calendar)
        let initials = DeskPad.weekdayInitials(calendar: calendar)
        let current = calendar.component(.day, from: day)
        VStack(spacing: 0) {
            Rectangle().fill(PaperPage.ink.opacity(0.12)).frame(height: 0.75).padding(.bottom, 4 * scale)
            row(initials.symbols.enumerated().map { index, symbol in
                Cell(text: symbol, bold: true, tint: index == initials.sundayIndex ? Theme.accent : PaperPage.ink.opacity(0.7),
                     circled: false)
            })
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                row(week.enumerated().map { index, number in
                    Cell(text: number.map(String.init) ?? "", bold: false,
                         tint: index == initials.sundayIndex ? Theme.accent : PaperPage.ink.opacity(0.85),
                         circled: number == current)
                })
            }
        }
        .accessibilityHidden(true)
    }

    private struct Cell {
        let text: String
        let bold: Bool
        let tint: Color
        let circled: Bool
    }

    private func row(_ cells: [Cell]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                Text(cell.text)
                    .font(Theme.font(9.5, scale, weight: cell.bold || cell.circled ? .bold : .regular))
                    .foregroundStyle(cell.circled ? Theme.accent : cell.tint)
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)
                    .frame(height: 14 * scale)
                    .background {
                        if cell.circled {
                            Circle().strokeBorder(Theme.accent, lineWidth: 1.2).frame(width: 15 * scale, height: 15 * scale)
                        }
                    }
            }
        }
    }
}

/// Blattform mit Abrisskante: oben eine Reihe halbrunder Aussparungen wie bei einem Abreißblock,
/// unten abgerundete Ecken.
private struct PerforatedPage: Shape {
    var radius: CGFloat
    var notch: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let pitch = notch * 3.4
        let count = max(1, Int((rect.width - 2 * radius) / pitch))
        let first = rect.minX + (rect.width - CGFloat(count - 1) * pitch) / 2
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        for index in 0..<count {
            let centerX = first + CGFloat(index) * pitch
            path.addLine(to: CGPoint(x: centerX - notch, y: rect.minY))
            // Halbkreis nach unten ins Blatt.
            path.addArc(center: CGPoint(x: centerX, y: rect.minY), radius: notch,
                        startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
                          control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - radius),
                          control: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
