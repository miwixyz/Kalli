import Foundation

/// Die drei Gruppen der Tagesliste. Zuklappbar sind „Ganztägig" und „Aufgaben".
enum AgendaGroupKind: String, CaseIterable, Sendable {
    case allDay, timed, tasks

    var title: String {
        switch self {
        case .allDay: "Ganztägig"
        case .timed: "Termine"
        case .tasks: "Aufgaben"
        }
    }

    var isCollapsible: Bool { self != .timed }

    /// Ab Werk: Aufgaben, Ganztägig, Termine.
    nonisolated static let defaultOrder: [AgendaGroupKind] = [.tasks, .allDay, .timed]

    /// Jede Gruppe genau einmal: Doppelte raus, Fehlende (z. B. aus einer älteren Version)
    /// in Werksreihenfolge hinten an. Leer → Werksreihenfolge.
    nonisolated static func normalized(_ order: [AgendaGroupKind]) -> [AgendaGroupKind] {
        var seen = Set<AgendaGroupKind>()
        let unique = order.filter { seen.insert($0).inserted }
        return unique + defaultOrder.filter { !seen.contains($0) }
    }

    nonisolated static func moved(_ group: AgendaGroupKind, by offset: Int,
                                  in order: [AgendaGroupKind]) -> [AgendaGroupKind] {
        var list = normalized(order)
        guard let from = list.firstIndex(of: group) else { return list }
        let to = from + offset
        guard list.indices.contains(to) else { return list }
        list.swapAt(from, to)
        return list
    }
}
